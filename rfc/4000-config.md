# 4000 — Config

How settings are resolved. **Status: implemented** in `src/config.nim`.

## Resolution order (step by step)

1. Start from built-in defaults (`defaultConfig()`).
2. If `nimo.json` exists in the working directory, its keys override defaults.
3. Environment variables (`NIMO_*`) are applied on top — highest priority.

So: **env > nimo.json > defaults**.

## Keys (as coded)

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
  "threads": 8,

  // Backend (see 7500-gpu.md)
  "backend": "cuda",          // "cpu" | "cuda" | "vulkan" (also accepts "nvidia"/"amd")
  "lib": "",                  // explicit librwkv.so path (overrides backend default)
  "gpuLayers": 99,            // layers offloaded to VRAM

  // Model cache (see 8150-quantization.md)
  "quant": "Q4_K",            // "" = load as-is; else raw -> quantize -> cache
  "modelCacheDir": ".nimo/model-cache",

  // State bake (see 8000-state-bake.md)
  "systemPrompt": "You are nimo, a helpful AI.",
  "bakeContext": true,        // resume baked state; bake on miss
  "stateCacheDir": ".nimo/state-cache"
}
```

## Env overrides

`NIMO_MODEL`, `NIMO_VOCAB`, `NIMO_GPU_LAYERS`, `NIMO_QUANT`,
`NIMO_MODEL_CACHE`, `NIMO_STATE_CACHE`, `NIMO_SYSTEM_PROMPT`,
`NIMO_BAKE_CONTEXT=1`, `NIMO_MAX_TOKENS`, `NIMO_THREADS`,
`NIMO_BACKEND=cpu|cuda|vulkan`, `NIMO_LIB=<path>`,
`NIMO_SMOKE=1`, `NIMO_SMOKE_PROMPT`.

Boolean flags accept `1`/`true`/`yes`.

## Backend parsing

`parseBackendKind` accepts: `cpu`, `cuda` (or `nvidia`), `vulkan` (or `amd`).
Unknown values raise an error.

## Workspace config

Each workspace also has a `config.toml` (created by `workspace.nim`) with the
same model/generation keys plus story rules (`minChapterWords`, `minParagraphs`,
`maxRepeats`) and pipeline limits (`maxIterations`, `critiqueRounds`).

## See Also

- [7500-gpu.md](7500-gpu.md) — backend / gpuLayers
- [8150-quantization.md](8150-quantization.md) — quant / modelCacheDir
- [8000-state-bake.md](8000-state-bake.md) — systemPrompt / bakeContext / stateCacheDir
