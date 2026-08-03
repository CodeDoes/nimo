# Plan: CUDA Fixes (if needed)

## Potential Issues

1. **LD_LIBRARY_PATH**: Must include `rwkv.cpp` and `rwkv.cpp/ggml/src`
2. **GPU state**: NVIDIA GPU must be in healthy state (not P8 with "needs reset")
3. **VRAM**: Model is 2.2 GB, GPU has 4 GB - should fit

## Fixes Applied

- Built `rwkv.cpp` with `-DRWKV_CUBLAS=ON -DCMAKE_CUDA_ARCHITECTURES="86"`
- Added CUDA toolkit packages to devenv.nix
- Backend selection properly routes to `rwkv.cpp/librwkv.so`

## Verification

Run `nimble run generate --backend cuda --model models/...-q4k.bin --prompt "test"` - should show CUDA device detection and generate tokens.
