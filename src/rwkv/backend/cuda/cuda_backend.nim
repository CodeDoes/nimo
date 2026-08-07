## NVIDIA CUDA backend provider.
##
## Validates CUDA availability, VRAM, and quant compatibility.
## Errors explicitly if the desired load strategy cannot work.

import std/[os, strformat]
import config, rwkv/model/header, gpu, rwkv/backend/types

const
  CudaMinVramMiB* = 2048         # minimum VRAM for any useful inference

proc cudaBackend*(): RwkvBackend =
  RwkvBackend(kind: bkCuda, name: "cuda",
              libPath: "rwkv.cpp/librwkv_cuda.so",
              defaultGpuLayers: 99)

proc checkCudaLoad*(backend: RwkvBackend, modelPath: string,
                    loadStrategy: string, requestedLayers: int): string =
  ## Validates CUDA load feasibility. Returns error message or "" if OK.
  if not fileExists(modelPath):
    return "Model not found: " & modelPath

  let h = readModelHeader(modelPath)
  if not isValidHeader(h):
    return "Invalid model header in: " & modelPath

  # Check CUDA driver
  let gpu = gpuProbe()
  if gpu.status == gpuUnknown:
    return "No NVIDIA CUDA driver found. Install NVIDIA drivers."
  if gpu.status == gpuUnusable:
    return &"GPU unusable: {gpu.detail}"

  # Check VRAM
  let freeVram = freeVramMiB()
  if freeVram < 0:
    return "Could not query VRAM"

  let modelMiB = modelSizeMiB(h)

  if freeVram < CudaMinVramMiB:
    return &"Insufficient VRAM: need at least {CudaMinVramMiB} MiB, found {freeVram} MiB"
  if modelMiB > freeVram:
    return &"Model too large for VRAM: {modelMiB} MiB > {freeVram} MiB free. " &
           "Try a smaller quant (Q4_K -> Q4_0)."

  # Validate requested layers fit
  if requestedLayers > int(h.nLayer):
    return &"Requested layers ({requestedLayers}) exceeds model layers ({h.nLayer})"

  return ""  # OK
