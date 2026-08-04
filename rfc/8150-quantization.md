# 8150 — Quantization

Model quantization policy and the model cache. **Status: implemented** in
`src/model_cache.nim` / `src/rwkv/quant/cache.nim` and `src/quantize.nim`.

## The default model

**Q4_K** (~2.2 GB for the 2.9B model). It fits the 4 GB RTX 2050 VRAM, leaving
room for activations and the 16K-context state, and is ~7× faster than CPU.

| Format | Size (2.9B) | Fits 4 GB fully? | Notes |
|--------|-------------|------------------|-------|
| FP16   | 5.9 GB      | No (partial)     | Reference; source of all quants |
| Q8_0   | ~2.9 GB     | Yes              | Near-FP16 quality |
| Q5_K   | ~2.5 GB     | Yes              | Good quality |
| **Q4_K** | **2.2 GB** | **Yes**          | **Default — best quality per bit** |
| Q4_1   | ~2.1 GB     | Yes              | Legacy 4-bit |
| Q4_0   | ~2.0 GB     | Yes              | Legacy 4-bit, lowest quality |

## The workflow

```
.pth (PyTorch) -> convert_pytorch_to_ggml.py -> FP16 .bin -> quantize.py -> Q4_K .bin
```

`nimo quantize <input> <format> <output>`:
1. Read the 24-byte GGML header (magic `ggmf`, version, n_vocab, n_embed,
   n_layer, data_type).
2. Reject non-raw input ("already quantized") and invalid headers.
3. Bind the backend library, run `quantizeModelFile`, report sizes + ratio.

## The model cache (raw → quantize → cache)

`ensureQuantized(rawPath, format)` — used by the harness before loading:

1. Read the header. **Already quantized** → use the file as-is.
2. **Raw** → compute a fast content signature (size + mtime + first 512 bytes
   hashed — hashing a multi-GB file every run is too slow).
3. Cached file `<cacheDir>/<sig12>-<format>.bin` exists → reuse it.
4. Not cached → quantize the raw model into the cache once, then use it.

The cache is content-addressed and idempotent: re-runs skip quantization.

## VRAM budget

`src/gpu.nim` queries free VRAM (`cuMemGetInfo`) and the model header (n_layer)
so GPU layers can be clamped to fit — rwkv.cpp SIGSEGVs on VRAM overcommit.

## See Also

- [8000-state-bake.md](8000-state-bake.md) — the state cache that pairs with this
- [7500-gpu.md](7500-gpu.md) — GPU probe + layer policy
- [4000-config.md](4000-config.md) — `quant`, `modelCacheDir`
