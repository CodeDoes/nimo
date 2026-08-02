## What is this file for?

Dependency graph and external requirements.

## Nim Packages (via nimble)

| Package   | Purpose                                     |
|-----------|---------------------------------------------|
| `illwave` | Terminal buffer / TUI primitives            |
| `nimwave` | Node-based TUI framework (wrapper over illwave) |

Both are from `https://github.com/ansiwave/` (same org as this project).

## C/C++ Dependencies

| Library      | Purpose                            | Source                          |
|--------------|------------------------------------|---------------------------------|
| `librwkv.so` | RWKV-7 model inference engine      | `rwkv.cpp` submodule (not tracked) |
| `libstdc++`  | C++ stdlib                         | system                          |
| `libopenmp`  | Threading                          | system                          |
| `ggml`       | Tensor computation (inside rwkv.cpp) | rwkv.cpp submodule            |

## Model Files

| File | Purpose |
|------|---------|
| `models/*.bin` | GGML Q4_0 quantized RWKV-7 weights (2.9B params) |
| `rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt` | WorldTokenizer vocabulary |

## Build Chain

```
rwkv.cpp/ (git submodule, not on disk)
  └── cmake + make → librwkv.so
        ↓
nimble build_all
  ├── nim c → build/main
  ├── nim c → build/generate
  ├── nim c → build/chat
  ├── nim c → build/bake_state
  └── nim c → build/nimwave_app
```

## Runtime Dependencies

- NVIDIA GPU with CUDA (for GPU-accelerated inference, `nGpuLayers=99`)
- Vulkan loaders (for ggml GPU backend)
- Terminal with UTF-8 and box-drawing character support
