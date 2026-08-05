# AGENTS.md — nimo

AI harness for local RWKV-7 inference (Nim). Deterministic harness wrapping a
non-deterministic model: `user -> pipeline -> chat/tool call -> answer`.
Sessions follow the pi-agent JSONL message-tree format (parentId chains).

## Project overview

- **Nim 2.2.10** app; model inference via `rwkv.cpp` (C/C++ backend, dlopen'd `librwkv.so`).
- Model: `models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin` (Q4_K quant of
  `~/Documents/models/rwkv7-g1i_preview5031-2.9b-20260729-ctx16384.pth`,
  ~2.2 GB — fits the 4 GB RTX 2050). FP16 variant (`-f16.bin`, 5.9 GB) is too
  big for full-GPU offload; the harness clamps `gpuLayers` to fit.
  Vocab: `rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt`.
- GPU: NVIDIA GeForce RTX 2050 (Ampere, sm_86, 4 GB) on a hybrid-graphics laptop
  (AMD Vega is boot VGA).

## Commands (run inside `devenv shell`)

```bash
devenv shell                 # enter dev env (nim, cmake, CUDA toolkit, python+torch)
devenv shell build-cuda      # rebuild rwkv.cpp with CUDA (MULTI-ARCH: 86;80;75;89 — slow!)
devenv shell build-vulkan    # rebuild rwkv.cpp with Vulkan/CLBlast (needs AMD OpenCL/CVu runtime)
devenv shell unit            # nimble task / run ./build/unit (offline, no model needed)
devenv shell build-all       # nimble build
```

Builds go to `build/`. Example commands in `src/` are compiled with:

```bash
# online (real model):
nim c --path:src -o:build/harness src/harness_main.nim
# offline (stub generator, no rwkv.cpp):
nim c --path:src -d:harnessOffline -o:build/unit src/unit.nim
```

## Smoke test (CPU / NVIDIA / AMD)

Fast single-shot backend check (no agent loop): loads the model, generates a
short reply, reports PASS/FAIL + wall time.

```bash
devenv shell scripts/smoke_test.sh
# cpu     -> --backend cpu (PASS, ~7s)
# nvidia  -> --backend cuda (PASS, ~4s)
# amd     -> --backend vulkan (PASS, ~6s)
#
# All three run through the single controlled path:
#   nimo.json config > explicit --backend flag > rwkv default > backend modules
```

The harness's `--smoke --backend <kind> --prompt "..." --max-tokens n` single-shot
mode also benchmarks a backend directly (an explicit flag, not env vars).

```bash
# online (real model):
nim c --path:src -o:build/harness src/harness_main.nim
# offline (stub generator, no rwkv.cpp):
nim c --path:src -d:harnessOffline -o:build/unit src/unit.nim
```

Run the harness with the rwkv libs on the loader path:

```bash
LD_LIBRARY_PATH="rwkv.cpp:rwkv.cpp/ggml/src:rwkv.cpp/ggml/src/ggml-cuda:$LD_LIBRARY_PATH" ./build/harness
```

## Backend Selection (RFC 7500)

Runtime backend is selected in one controlled place (`src/rwkv.nim`). Priority,
most-specific first:
1. Explicit `--backend` flag (CLI arg, same convention as `generate.nim`)
2. Config file: `nimo.json` → `"backend"` / `"lib"`
3. Compile-time default: `-d:rwkvDefaultBackend=cuda`
4. Backend modules (`src/rwkv_cpu/cuda/vulkan.nim`) — lowest authority

That's the whole precedence — no more layers above it. (Env vars are fine when
they earn their place; they are simply not needed here, so the core path stays
config + flags.)

Switch point: `selectBackend(cfg)` → `bindBackend(libPath)` (one dlopen per session).

Per-backend GPU policy:
| backend | GPU probe | gpuLayers |
|---------|-----------|----------|
| `cpu`   | skip      | 0        |
| `cuda`  | required  | clamped  |
| `vulkan`| skip      | cfg.gpuLayers |

### CLI generate command

```bash
# Direct binary
./build/generate --backend cpu|cuda|vulkan --max-length 20 "prompt"

# Via harness dispatcher
./build/harness generate --backend vulkan --max-length 20 "prompt"
```

### Measured performance (8 tokens, this machine)

| Backend | Time      | Notes |
|---------|-----------|-------|
| CPU     | ~15s      | OpenMP, no GPU |
| CUDA    | ~1s       | RTX 2050 (may fail if GPU state is bad) |
| Vulkan  | ~0.9s     | AMD Radeon Graphics (RADV) |

Note: CUDA may fail with `CUDA driver is a stub library` on this hybrid-
graphics laptop when the NVIDIA GPU is in a suspended state. Use `vulkan`
or `cpu` as fallback. See `src/gpu.nim` for the probe logic.

The harness detects the GPU state on startup via the CUDA Driver API
(`src/gpu.nim`, `gpuProbe`), *before* loading the model — so a broken GPU gives a
clean, actionable message instead of a crash.

- Healthy         -> `[gpu] OK — GPU usable ...` (uses `gpuLayers`).
- Unusable        -> `[gpu] ERROR ...` and it **refuses to start by default**.
- `gpuUnknown`    -> no NVIDIA driver found; treated like unusable for the policy.

A manual sanity check is still worth doing first:

```bash
nvidia-smi --query-gpu=name,pstate,utilization.gpu,memory.used --format=csv
```

- Healthy: a real pstate (`P0`/`P8`) and utilization numbers.
- Broken: `[GPU requires reset]` / all `N/A` — CUDA init fails with
  `no CUDA-capable device is detected` even though nvidia-smi lists the card.

Fix requires root: reboot, or
`sudo modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia && sudo modprobe nvidia`.
Laptop GPUs don't support `nvidia-smi --gpu-reset`.

## CPU fallback is opt-in (config-gated)

The harness only runs on CPU when explicitly allowed. Default is GPU-required.

```jsonc
// nimo.json (repo root; see src/config.nim for all keys)
{
  "model": "models/rwkv7-g1i-2.9b-20260729-ctx16384-f16.bin",
  "allowCpuFallback": true,     // opt-in: run on CPU if the GPU is unusable
  "quant": "Q4_K",              // raw -> quantize -> cache (src/model_cache.nim)
  "modelCacheDir": ".nimo/model-cache",
  "systemPrompt": "You are nimo.",   // baked into state cache (RFC 8000)
  "bakeContext": true,               // resume baked state; bake on miss
  "stateCacheDir": ".nimo/state-cache"
}
```

Config comes from `nimo.json` only (no env-var precedence chain — env
configuration was deliberately dropped for one source of truth). The `--backend`
flag is the one explicit override. If the GPU is unusable, the harness prints
the diagnosis + fix and exits cleanly.

To rebuild CUDA fast for THIS machine only (sm_86), do NOT use `build-cuda`
(compiles 4 archs): configure with just `86`:

```bash
cd rwkv.cpp && rm -rf CMakeCache.txt CMakeFiles
cmake . -DRWKV_CUBLAS=ON -DCMAKE_CUDA_ARCHITECTURES="86" -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

## Model conversion gotchas

- `.pth` -> GGML `.bin`: `python3 rwkv.cpp/python/convert_pytorch_to_ggml.py <src.pth> <out.bin> FP16`.
- FP16 -> Q4_K (default runtime model; 4-bit, ~2.2 GB, fits 4 GB VRAM):
  `devenv shell python3 rwkv.cpp/python/quantize.py <f16.bin> <q4k.bin> Q4_K`
  (needs librwkv.so on the loader path — run from repo root, lib is at `rwkv.cpp/librwkv.so`).
- The nix python's numpy is broken (`undefined symbol: zgesv_`) — preload OpenBLAS:
  `LD_PRELOAD=/nix/store/*openblas*/lib/libopenblas.so python3 ...`
  (glob may match several; any works).
- torch 2.12.0 lives in the devenv shell; the bare `python3` outside it may not import torch.
- If the GPU can't hold the whole model, `safeGpuLayers` (in `src/gpu.nim`)
  clamps `gpuLayers` to fit free VRAM (reads the file header: 6 u32,
  magic `ggmf`, `n_layer` at offset 16) — rwkv.cpp SIGSEGVs on overcommit, so
  don't bypass the clamp.

## Unit Tests

`src/unit.nim` — 61 checks, offline (scripted `genStub`, no model):

1. **Tool calling** — detect `[tool] run_pipeline {...}`, dispatch, feed result back, final answer.
2. **Loop termination** — max-iteration guard (8); a script that never stops calling
   tools must abort (`turn.aborted == true`).
3. **Session tree** — JSONL: header + 4 messages
   (user -> tool_call -> tool_result -> text), `stopReason: "toolUse"`, parentId chain.

Note: `run_pipeline` consumes one generator response internally (pipeline step
generation), so eval scripts must budget 2 responses per harness iteration.

## Tool-call syntax (harness parses 3 forms)

The model is prompted to emit:
```
[tool] run_pipeline {"intent": "write a poem about roses"}
```
Also parsed: `<tool_call>{...}</tool_call>` and bare JSON-object lines
(`{"name": ..., "arguments": ...}` or `{"arguments":{"prompt":...}}`).
Small RWKV models frequently emit bare JSON instead of `[tool]` — the fallbacks exist for that.

## Architecture

- `src/session_manager.nim` — messages, tool registry, JSONL save, `genStub`.
  `-d:harnessOffline` strips the RWKV backend (unit tests run without rwkv.cpp).
- `src/gpu.nim` — CUDA Driver API probe (`gpuProbe`) + fallback policy (`decideGpu`).
- `src/model_cache.nim` — raw -> quantize -> cache: content-addressed quantized
  model cache (sha1 of size/mtime/head), auto-quantize via `quant` config.
- `src/state_cache.nim` — context-read -> state -> cache (RFC 8000): baked state
  keyed by (model sig | vocab hash | context); resume-on-miss via `bakeContext`.
- `src/harness.nim` — agent loop + tool parsing + CLI (loads `nimo.json`).
- `src/pipeline.nim` — `run_pipeline` tool: steps, target files, state in `.nimo/`.
- `src/session.nim` — low-level RWKV session (real generation).
- `src/config.nim` — `NimoConfig` (model/vocab/layers/allowCpuFallback/quant/caches
  + env overrides).
- `devenv.nix` / `devenv.yaml` / `flake.nix` — dev env (allowUnfree is set in
  `devenv.yaml`; CUDA toolkit via `cudaPackages`).

## Conventions

- RFC-first: behavior is specified in `rfc/` (4-digit numbering, e.g. 3000-pipeline,
  9300-eval). Read the relevant RFC before changing behavior.
- Session JSONL must stay **one JSON object per line** (compact `$j`, not `pretty`).
- Don't break `-d:harnessOffline` builds — the eval suite depends on it.
- Keep tool handlers deterministic; model output is the only non-determinism.
- Agent work should leave the unit test suite green: `devenv shell unit`.
