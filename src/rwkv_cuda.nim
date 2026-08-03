## NVIDIA CUDA backend provider (RFC 7500).
##
## LOWEST authority in backend selection: only knows where its librwkv.so (the
## CUDA build, rwkv.cpp root) lives. Selection is decided upstream by
## `rwkv.selectBackend`.

import ./config
import ./rwkv_cpu   # for the shared RwkvBackend type

proc cudaBackend*(): RwkvBackend =
  RwkvBackend(kind: bkCuda, name: "cuda",
              libPath: "rwkv.cpp/librwkv.so",
              defaultGpuLayers: 99)