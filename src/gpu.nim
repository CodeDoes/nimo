## GPU/CUDA diagnostics for nimo.
## Probes the NVIDIA driver directly (via the CUDA Driver API in libcuda.so.1)
## so the harness can detect and report GPU state *without* going through
## rwkv.cpp. This is deliberate: when the GPU is broken the CUDA runtime fails
## with "no CUDA-capable device is detected" (e.g. driver reports the GPU needs
## a reset), and we want a clean, actionable message instead of a crash.

import std/[dynlib, os]

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

## Convenience for callers that just want to pick a GPU-layers count.
## CPU fallback only happens if allowCpuFallback is explicitly enabled;
## otherwise the caller must treat an unusable GPU as fatal.
type
  GpuDecision* = enum
    gdUseGpu      ## GPU is fine, use configured layers
    gdCpuFallback ## GPU unusable + allowCpuFallback: run on CPU (layers = 0)
    gdBlocked     ## GPU unusable + fallback NOT allowed: caller must refuse

proc decideGpu*(r: GpuReport, wantGpuLayers: int, allowCpuFallback: bool): tuple[decision: GpuDecision, layers: int] =
  case r.status
  of gpuAvailable:
    result = (gdUseGpu, wantGpuLayers)
  of gpuUnusable:
    if allowCpuFallback:
      result = (gdCpuFallback, 0)
    else:
      result = (gdBlocked, wantGpuLayers)
  of gpuUnknown:
    # No NVIDIA driver found at all — treat like unusable for the fallback policy.
    if allowCpuFallback:
      result = (gdCpuFallback, 0)
    else:
      result = (gdBlocked, wantGpuLayers)

## ---- VRAM-aware GPU-layer clamping ----
## rwkv.cpp SIGSEGVs (null deref) if asked to put more model on the GPU than
## fits in VRAM, so before loading we clamp n_gpu_layers to what actually fits.

proc freeVramMiB*(): int =
  ## Free VRAM on device 0 in MiB via cuMemGetInfo, or -1 if unavailable.
  let lib = loadLib("libcuda.so.1")
  if lib == nil: return -1
  defer: unloadLib(lib)
  type CuMemGetInfo = proc(free, total: ptr int64): cint {.cdecl.}
  let cuMemGetInfo = cast[CuMemGetInfo](symAddr(lib, "cuMemGetInfo"))
  if cuMemGetInfo == nil: return -1
  var freeMem, totalMem: int64
  if cuMemGetInfo(addr freeMem, addr totalMem) != cuSuccess: return -1
  return int(freeMem div (1024 * 1024))

proc modelFileInfo*(modelPath: string): tuple[nLayers: int, bytes: int64] =
  ## Reads the rwkv.cpp file header (6 u32: magic,version,vocab,embed,layers,dtype)
  ## straight off disk + reports the file size — no library load required.
  if not fileExists(modelPath): return
  result.bytes = getFileSize(modelPath)
  var f: File
  if f.open(modelPath, fmRead):
    var buf: array[24, uint8]
    if f.readBytes(buf, 0, 24) == 24:
      # magic must be GGML (0x67676d66 = 'ggmf')
      if buf[0] == 0x66 and buf[1] == 0x6d and buf[2] == 0x67 and buf[3] == 0x67:
        result.nLayers = int(buf[16]) or (int(buf[17]) shl 8) or
                         (int(buf[18]) shl 16) or (int(buf[19]) shl 24)
    f.close()

proc safeGpuLayers*(modelPath: string, requested: int, freeVram: int): int =
  ## Returns a gpu-layers count: the requested one if the model fits in VRAM
  ## with headroom, otherwise a proportional clamp based on size / n_layers.
  ## Reserved headroom covers activations + the KV/state cache.
  const headroomMiB = 1536
  let info = modelFileInfo(modelPath)
  if info.nLayers <= 0 or info.bytes <= 0 or freeVram <= 0:
    return requested
  let modelMiB = int(info.bytes div (1024 * 1024))
  if modelMiB + headroomMiB <= freeVram:
    return requested
  let perLayer = modelMiB div info.nLayers
  if perLayer <= 0: return 0
  let usable = freeVram - headroomMiB
  if usable <= 0: return 0
  return min(requested, usable div perLayer)