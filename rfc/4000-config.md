# 4000 — Config

`NimoConfig` (src/config.nim) is loaded from `nimo.json` (or `NIMO_*` env vars),
with env applied on top of the file.

## Keys

```jsonc
// nimo.json (repo root)
{
  // Model
  "model": "models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin",
  "vocab": "rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt",

  // Generation
  "temperature": 0.7,
  "topP": 0.7,
  "maxTokens": 200,

  // Backend (see 7500-gpu.md)
  "backend": "cuda",          # "cpu" | "cuda" | "vulkan"
  "lib": "",                  # explicit librwkv.so path (overrides backend default)
  "gpuLayers": 99,            // layers offloaded to VRAM (auto-clamped to fit)
  "allowCpuFallback": false,  // opt-in: run on CPU if the GPU is unusable

  // Model cache (see 8150-quantization.md)
  "quant": "Q4_K",            // "" = load model as-is; else raw->quantize->cache
  "modelCacheDir": ".nimo/model-cache",

  // State bake (see 8000-state-bake.md)
  "systemPrompt": "You are nimo, a helpful AI.",
  "bakeContext": true,
  "stateCacheDir": ".nimo/state-cache"
}
```

## Env overrides (applied on top of the file)

`NIMO_MODEL`, `NIMO_VOCAB`, `NIMO_GPU_LAYERS`, `NIMO_ALLOW_CPU_FALLBACK=1`,
`NIMO_QUANT`, `NIMO_MODEL_CACHE`, `NIMO_STATE_CACHE`, `NIMO_SYSTEM_PROMPT`,
`NIMO_BAKE_CONTEXT=1`, `NIMO_MAX_TOKENS`,
`NIMO_BACKEND=cpu|cuda|vulkan`,
`NIMO_LIB=<path>`,
`NIMO_SMOKE=1`, `NIMO_SMOKE_PROMPT`.
Boolean flags accept `1`/`true`/`yes`.

## Personas

| Persona | Purpose |
|---------|---------|
| `user_intent` | Parse vague user requests into structured tasks |
| `writer` | Generate creative content |
| `editor` | Refine and improve content |
| `critique` | Evaluate quality |
| `planner` | Create execution plans |
| `coder` | Generate code |

## See Also

- [7500-gpu.md](7500-gpu.md) — gpuLayers / allowCpuFallback
- [8150-quantization.md](8150-quantization.md) — quant / modelCacheDir
- [8000-state-bake.md](8000-state-bake.md) — systemPrompt / bake / stateCacheDir
- [3000-pipeline.md](3000-pipeline.md) — config used by pipelines
