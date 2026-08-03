## rwkv/backend/types.nim — Shared backend types.
##
## Declares RwkvBackend and RwkvBackendKind for all backend modules.

import ../../config

type
  RwkvBackend* = object   # declared here + re-exported; kept in config for enum
    ## A concrete runtime backend: which librwkv.so and how to offload layers.
    kind*: RwkvBackendKind
    name*: string          # human label, e.g. "cpu"
    libPath*: string       # librwvcpp.so for this backend (lowest-authority default)
    defaultGpuLayers*: int # GU backend hint (0 = CPU only)
