# Plan: DevEnv CUDA Setup

## Current State

`devenv.nix` already includes:
- `cudaPackages.cuda_nvcc`
- `cudaPackages.cuda_cudart`
- `cudaPackages.libcublas`
- `cudaPackages.cuda_cupti`

## LD_LIBRARY_PATH

The devenv sets:
```
LD_LIBRARY_PATH = /usr/lib/x86_64-linux-gnu:/run/opengl-driver/lib:...
```

But missing: `rwkv.cpp` and `rwkv.cpp/ggml/src` paths.

## Fix Needed

Add to devenv.nix env.LD_LIBRARY_PATH:
```
:rwkv.cpp:rwkv.cpp/ggml/src:.
```

Or use the build scripts to set it up properly.

## Alternative: Wrapper Script

Create `scripts/nimo-cuda` that sets LD_LIBRARY_PATH and runs commands.
