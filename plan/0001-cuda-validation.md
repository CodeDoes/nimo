# Plan: CUDA Validation

## Status: CUDA WORKING ✓

All validation commands passed successfully.

## Validation Results

### 1. Quantize
```bash
nimble quantize models/rwkv7-g1i-2.9b-20260729-ctx16384-f16.bin Q4_K models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin
```
- Model converted: 5625 MiB → 2175 MiB (38.7%)
- Time: 143.70s
- Output: `models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin` (2.2 GB)

### 2. Generate with CUDA
```bash
nimble generate --model models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin --device gpu-0 --prompt "System: You are" --max-tokens 10 --backend cuda
```
- Backend: cuda
- Device: gpu-0 (NVIDIA GeForce RTX 2050, compute capability 8.6)
- Generated 10 tokens in 2.678s (267.8 ms/token)
- CUDA device detected: yes

### 3. Eval
```bash
nimble eval --model models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin --device gpu-0 --backend cuda
```
- 34/34 tests passed
- Includes GPU-related tests (gpuAvailable, gpuUnusable, gpuLayers)

### 4. Chat with CUDA
```bash
nimble chat --model models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin --device gpu-0 --backend cuda
```
- Backend: cuda
- Device: gpu-0
- Interactive chat works with CUDA backend
- Generated response: "Hello! How can I assist you?"

## DevEnv Notes

The devenv.nix already includes CUDA packages:
- `cudaPackages.cuda_nvcc`
- `cudaPackages.cuda_cudart`
- `cudaPackages.libcublas`
- `cudaPackages.cuda_cupti`

The key requirement is setting `LD_LIBRARY_PATH` to include:
- `rwkv.cpp`
- `rwkv.cpp/ggml/src`

## Changes Made

1. Fixed `src/chat.nim` to support `--backend` and `--device` flags (matching generate.nim)
2. Added proper backend selection and binding to chat command
3. Model quantization completed successfully

## Known Issues

- GPU memory usage not consistently visible in nvidia-smi (may be due to VMM or quick allocation/deallocation)
- Intermittent OOM errors when running multiple commands in quick succession (GPU state may need reset)
