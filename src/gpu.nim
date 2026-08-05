## GPU/CUDA diagnostics for nimo.
## Probes the NVIDIA driver directly (via the CUDA Driver API in libcuda.so.1)
## so the harness can detect and report GPU state *without* going through
## rwkv.cpp. This is deliberate: when the GPU is broken the CUDA runtime fails
## with "no CUDA-capable device is detected" (e.g. driver reports the GPU needs
## a reset), and we want a clean, actionable message instead of a crash.

import std/[dynlib]
import ./rwkv/model/header

# Opaque CUDA Driver API handles (we never dereference them)
type
  CUdevice* = distinct int
  CUcontext* = distinct int

type
  GpuStatus* = enum
    gpuUnknown    ## no native CUDA driver library found (e.g. open-source/unsupported)
    gpuUnusable   ## driver present but reports no usable device (needs reset / broken)
    gpuAvailable  ## >= 1 CUDA device usable

  GpuReport* = object
    status*: GpuStatus
    deviceCount*: int   # -1 if can't determine
    detail*: string     # human-readable diagnostics

# CUDA Driver API result codes (subset we care about)
const
  cuSuccess = 0
  cuErrorNoDevice = 100      # CUDA_ERROR_NO_DEVICE
  cuErrorNotInitialized = 3
  cuErrorInvalidValue = 1

proc gpuProbe*(): GpuReport =
  ## Loads libcuda.so.1 and calls cuInit + cuDeviceGetCount.
  result.deviceCount = -1
  let lib = loadLib("libcuda.so.1")
  if lib == nil:
    result.status = gpuUnknown
    result.detail = "No NVIDIA CUDA driver library (libcuda.so.1) found on the loader path."
    return

  defer: unloadLib(lib)

  type
    CuInit = proc(flags: uint32): cint {.cdecl.}
    CuDevCount = proc(count: ptr cint): cint {.cdecl.}

  let cuInit = cast[CuInit](symAddr(lib, "cuInit"))
  let cuDevCount = cast[CuDevCount](symAddr(lib, "cuDeviceGetCount"))
  if cuInit == nil or cuDevCount == nil:
    result.status = gpuUnknown
    result.detail = "Driver library found, but it does not export cuInit/cuDeviceGetCount."
    return

  let initCode = cuInit(0)
  if initCode != cuSuccess:
    case initCode
    of cuErrorNoDevice:
      result.status = gpuUnusable
      result.detail = "Driver present but reports no CUDA-capable device (CUDA_ERROR_NO_DEVICE). " &
                      "nvidia-smi may list the GPU, but the driver cannot initialize it — " &
                      "often pstate is \"GPU requires reset\". Fix: reboot, or " &
                      "`sudo modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia && sudo modprobe nvidia`."
    else:
      result.status = gpuUnusable
      result.detail = "cuInit failed with code " & $initCode &
                      " (CUDA_ERROR_NOT_INITIALIZED=" & $cuErrorNotInitialized &
                      ", INVALID_VALUE=" & $cuErrorInvalidValue & ")."
    return

  var count: cint
  let countCode = cuDevCount(addr count)
  if countCode != cuSuccess or count <= 0:
    result.status = gpuUnusable
    result.deviceCount = int(count)
    result.detail = "Driver reports zero usable CUDA devices (cuDeviceGetCount=" & $countCode & ")."
    return

  result.status = gpuAvailable
  result.deviceCount = int(count)
  result.detail = $count & " CUDA-capable device(s) detected."

proc describe*(r: GpuReport): string =
  case r.status
  of gpuAvailable: "OK — GPU usable (" & r.detail & ")"
  of gpuUnusable:  "ERROR — GPU unusable: " & r.detail
  of gpuUnknown:   "WARN — " & r.detail

## GPU decision: either GPU is usable or we refuse to start.
## No fallbacks — GPU failure is fatal by default.
type
  GpuDecision* = enum
    gdUseGpu  ## GPU is fine, use configured layers
    gdBlocked ## GPU unusable: caller must refuse

proc decideGpu*(r: GpuReport, wantGpuLayers: int): tuple[decision: GpuDecision, layers: int] =
  case r.status
  of gpuAvailable:
    result = (gdUseGpu, wantGpuLayers)
  of gpuUnusable, gpuUnknown:
    result = (gdBlocked, wantGpuLayers)

## VRAM query only (no auto-clamping — caller decides).

proc freeVramMiB*(): int =
  ## Free VRAM on device 0 in MiB via cuMemGetInfo, or -1 if unavailable.
  let lib = loadLib("libcuda.so.1")
  if lib == nil: return -1
  defer: unloadLib(lib)
  type CuInit = proc(flags: cuint): cint {.cdecl.}
  type CuDeviceGet = proc(dev: ptr CUdevice; ordinal: cint): cint {.cdecl.}
  type CuCtxCreate = proc(ctx: ptr CUcontext; flags: cuint; dev: CUdevice): cint {.cdecl.}
  type CuMemGetInfo = proc(free, total: ptr int64): cint {.cdecl.}
  type CuCtxDestroy = proc(ctx: CUcontext): cint {.cdecl.}
  let cuInit = cast[CuInit](symAddr(lib, "cuInit"))
  let cuDeviceGet = cast[CuDeviceGet](symAddr(lib, "cuDeviceGet"))
  let cuCtxCreate = cast[CuCtxCreate](symAddr(lib, "cuCtxCreate"))
  let cuMemGetInfo = cast[CuMemGetInfo](symAddr(lib, "cuMemGetInfo"))
  let cuCtxDestroy = cast[CuCtxDestroy](symAddr(lib, "cuCtxDestroy"))
  if cuInit == nil or cuMemGetInfo == nil: return -1
  # cuMemGetInfo requires an initialized CUDA context (returns
  # CUDA_ERROR_INVALID_CONTEXT=201 otherwise) — so cuInit + cuCtxCreate
  # must precede it. Clean up the context after.
  if cuInit(0) != cuSuccess: return -1
  if cuDeviceGet == nil or cuCtxCreate == nil: return -1
  var dev: CUdevice
  if cuDeviceGet(addr dev, 0) != cuSuccess: return -1
  var ctx: CUcontext
  if cuCtxCreate(addr ctx, 0, dev) != cuSuccess: return -1
  var freeMem, totalMem: int64
  let ok = cuMemGetInfo(addr freeMem, addr totalMem) == cuSuccess
  # release the throwaway context (best-effort; ignore errors)
  if cuCtxDestroy != nil:
    discard cuCtxDestroy(ctx)
  if not ok: return -1
  return int(freeMem div (1024 * 1024))

proc resolveGpuLayers*(modelPath: string, requested: int = -1): int =
  ## Derive how many transformer layers to offload to GPU VRAM.
  ##
  ## There is NO magic "default layer count" — offload amount is derived from
  ## the model's own shape (header nLayer) and the GPU's free VRAM:
  ##   - requested < 0  -> offload all model layers that fit in VRAM
  ##   - requested == 0 -> CPU only (0 layers)
  ##   - requested > 0  -> explicit cap, still clamped to what VRAM holds
  ## Returns >= 0; -1 only if the model header can't be read.
  let h = readModelHeader(modelPath)
  if not isValidHeader(h) or h.nLayer == 0:
    return -1
  let modelLayers = int(h.nLayer)
  var want = if requested < 0: modelLayers else: requested
  if want <= 0:
    return 0
  if want > modelLayers:
    want = modelLayers
  # If we can query free VRAM and the whole model swims in it, that's enough.
  let freeVram = freeVramMiB()
  if freeVram <= 0:
    return want  # can't gauge VRAM — trust model layer bound
  let modelMiB = modelSizeMiB(h)
  if modelMiB <= freeVram:
    return modelLayers  # whole model fits: offload everything
  # Not enough VRAM for all layers — proportionally drop layers so the
  # offloaded subset approximates available memory (keep at least 1).
  let totalMiB = modelMiB  # embed+vocab+layers; layers dominate for RWKV
  let usableMiB = freeVram
  let keep = max(1, int(float(modelLayers) * float(usableMiB) / float(totalMiB)))
  result = if keep < want: keep else: want