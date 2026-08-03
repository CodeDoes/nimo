## AMD Vulkan backend provider (RFC 7500).
##
## rwkv.cpp built with GGML_VULKAN into rwkv.cpp/build-amd (see
## scripts/build/amd-vulkan.sh). LOWEST authority in backend selection; the
## decision is made upstream by `rwkv.selectBackend`.

import ./config
import ./rwkv_cpu   # for the shared RwkvBackend type

proc vulkanBackend*(): RwkvBackend =
  RwkvBackend(kind: bkVulkan, name: "vulkan",
              libPath: "rwkv.cpp/build-amd/librwkv.so",
              defaultGpuLayers: 99)