# 8150 — Quantization

Model quantization policy: which formats we ship, why Q4_K is the default,
and how the harness keeps the model inside the GPU's VRAM budget.

## Status

Implemented (commit: Q4_K default model + VRAM clamp). Evals cover the clamp.

## Decision

**Default runtime model is Q4_K.** The RTX 2050 has 4 GB VRAM. The FP16 model
is 5.9 GB and cannot be fully offloaded; Q4_K is ~2.2 GB and fits with room
for activations + the 16K-context state. GPU generation is ~7.5× faster than
CPU on this machine (7.1 s vs 53 s for a short answer).

| Format | Size (this 2.9B) | Fits 4 GB fully? | Notes |
|--------|------------------|------------------|-------|
| FP16   | 5.9 GB            | No (partial)     | Reference; source of all quants |
| Q8_0   | ~2.9 GB           | Yes              | Near-FP16 quality |
| Q5_K   | ~2.5 GB           | Yes              | Good quality |
| **Q4_K** | **2.2 GB**      | **Yes**          | **Default — best quality per bit of 4-bit** |
| Q4_1   | ~2.1 GB           | Yes              | Legacy 4-bit |
| Q4_0   | ~2.0 GB           | Yes              | Legacy 4-bit, lowest quality |

## Formats supported by rwkv.cpp

`python/quantize.py` accepts: `Q4_0`, `Q4_1`, `Q4_K`, `Q5_0`, `Q5_1`, `Q5_K`,
`Q8_0` (see `rwkv_cpp_shared_library.QUANTIZED_FORMAT_NAMES`).

## Workflow

```bash
# 1. .pth -> FP16 GGML (needs devenv python + torch; numpy broken -> preload OpenBLAS)
LD_PRELOAD=/nix/store/*openblas*/lib/libopenblas.so devenv shell python3 \
  rwkv.cpp/python/convert_pytorch_to_ggml.py src.pth models/rwkv7-...-f16.bin FP16

# 2. FP16 -> Q4_K (needs librwkv.so on the loader path; it is at rwkv.cpp/librwkv.so)
devenv shell python3 rwkv.cpp/python/quantize.py \
  models/rwkv7-...-f16.bin models/rwkv7-...-q4k.bin Q4_K
```

Keep the FP16 file as the canonical artifact; quants are derived, reproducible
outputs (record command + tool version in commit messages).

## File format (header)

`rwkv.cpp` models start with a flat header of 6 little-endian u32 (24 bytes):

| Offset | Field       |
|--------|-------------|
| 0      | magic = `0x67676d66` (`ggmf`, bytes `f m g g`) |
| 4      | version     |
| 8      | n_vocab     |
| 12     | n_embed     |
| 16     | **n_layer** |
| 20     | data_type   |

The harness reads `n_layer` + file size straight off disk (no library load) to
compute VRAM needs — see `modelFileInfo` in `src/gpu.nim`.

## VRAM budgeting

`safeGpuLayers(modelPath, requested, freeVram)`:

1. If model size + 1.5 GiB headroom ≤ free VRAM → use requested layers.
2. Otherwise clamp proportionally: `layers = (freeVRAM − headroom) / perLayer`
   where `perLayer ≈ modelMiB / n_layer`.

Headroom (1536 MiB) covers activations, the RWKV state/KV cache, and
ggml workspace. rwkv.cpp **SIGSEGVs** (null deref) if `cudaMalloc` OOMs, so the
clamp runs before `initRwkvModel` — never raise `gpuLayers` past what fits.

Free VRAM comes from `cuMemGetInfo` (driver API, `freeVramMiB` in `src/gpu.nim`).

## Model file naming

```
models/rwkv7-<arch>-<size>-<yyyymmdd>-ctx<ctxlen>-<quant>.bin
models/rwkv7-g1i-2.9b-20260729-ctx16384-f16.bin   # 5.9 GB, canonical FP16
models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin   # 2.2 GB, default
```

## Configuration

`src/config.nim` default: `models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin`.
Override per-run with `nimo.json` (`"model"`, `"gpuLayers"`) or `NIMO_MODEL` /
`NIMO_GPU_LAYERS`.

## Evals

`src/evals.nim`, GPU policy group (24 checks total):

- ample VRAM keeps requested layers
- tight VRAM clamps layers down (synthetic `ggmf` header on disk)

## See Also

- [8100-rwkv.md](8100-rwkv.md) — RWKV engine details
- [4000-config.md](4000-config.md) — model params in config
- [9300-eval.md](9300-eval.md) — eval suite
