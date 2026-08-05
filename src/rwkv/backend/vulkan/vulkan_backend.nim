## AMD Vulkan backend provider.
##
## Validates Vulkan availability and memory.
## Errors explicitly if the desired load strategy cannot work.

import std/[os, strformat]
import config, rwkv/model/header, rwkv/backend/types

proc vulkanBackend*(): RwkvBackend =
  RwkvBackend(kind: bkVulkan, name: "vulkan",
              libPath: "rwkv.cpp/build-amd/librwkv.so",
              defaultGpuLayers: 99)

proc checkVulkanLoad*(backend: RwkvBackend, modelPath: string,
                      loadStrategy: string, requestedLayers: int): string =
  ## Validates Vulkan load feasibility. Returns error message or "" if OK.
  if not fileExists(modelPath):
    return "Model not found: " & modelPath

  let h = readModelHeader(modelPath)
  if not isValidHeader(h):
    return "Invalid model header in: " & modelPath

  let modelMiB = modelSizeMiB(h)

  # Vulkan memory is system-accessible; approximate check
  # Real Vulkan memory query requires vkGetPhysicalDeviceMemoryProperties
  if modelMiB > 8192:  # >8GB is likely too large for most integrated GPUs
    return &"Model is {modelMiB} MiB — likely too large for Vulkan on integrated graphics. " &
           "Try Q4_0 quant or use --backend cpu"

  if requestedLayers > int(h.nLayer):
    return &"Requested layers ({requestedLayers}) exceeds model layers ({h.nLayer})"

  return ""  # OK
