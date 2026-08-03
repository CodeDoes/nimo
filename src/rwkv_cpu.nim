## CPU backend provider (RFC 7500).
##
## The CPU "backend" runs the same rwkv.cpp engine with GPU offload disabled
## (gpuLayers=0). This module is the LOWEST authority in backend selection:
## it only knows where its runtime librwkv.so lives. Which backend actually
## runs is decided by `rwkv.selectBackend` (config > env > rwkv default).

import ./config

type RwkvBackend* = object   # declared here + re-exported; kept in config for enum
  ## A concrete runtime backend: which librwkv.so and how to offload layers.
  kind*: RwkvBackendKind
  name*: string              # human label, e.g. "cpu"
  libPath*: string           # librwvcpp.so for this backend (lowest-authority default)
  defaultGpuLayers*: int     # GU backend hint (0 = CPU only)

proc cpuBackend*(): RwkvBackend =
  RwkvBackend(kind: bkCpu, name: "cpu",
              libPath: "rwkv.cpp/librwkv.so",  # CUDA build runs fine on CPU at gpuLayers=0
              defaultGpuLayers: 0)