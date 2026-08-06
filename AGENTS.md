# AGENTS.md — nimo

AI harness for local RWKV-7 inference (Nim). Deterministic harness wrapping a
non-deterministic model: `user -> pipeline -> chat/tool call -> answer`.
Sessions follow the pi-agent JSONL message-tree format (parentId chains).

> **Operating mode:** See [`MEGA_INSTRUCTIONS.md`](MEGA_INSTRUCTIONS.md) for
> UX/DX priorities, step-by-step run cadence, tracking conventions, and the
> decision framework. It supersedes this file when they conflict.

## Project overview

- **Nim 2.2.10** app; model inference via `rwkv.cpp` (C/C++ backend, dlopen'd `librwkv.so`).
- Model: `models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin` (Q4_K quant of
  `~/Documents/models/rwkv7-g1i_preview5031-2.9b-20260729-ctx16384.pth`,
  ~2.2 GB — fits the 4 GB RTX 2050). FP16 variant (`-f16.bin`, 5.9 GB) is too
  big for full-GPU offload; the harness clamps `gpuLayers` to fit.
  Vocab: `rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt`.
- GPU: NVIDIA GeForce RTX 2050 (Ampere, sm_86, 4 GB).

## Commands (run inside `devenv shell`)

```bash
devenv shell                 # enter dev env (nim, cmake, CUDA toolkit, python+torch)
devenv shell build_libs      # build CUDA and CPU backend libraries
devenv shell unit            # nimble task / run ./build/unit (offline, no model needed)
devenv shell build_all       # nimble build all binaries
```

Builds go to `build/`. Example commands in `src/` are compiled with:

```bash
# online (real model):
nim c --path:src -o:build/harness src/harness.nim
# offline (stub generator, no rwkv.cpp):
nim c --path:src -d:harnessOffline -o:build/unit src/unit.nim
```

Tool binaries in `src/` are standalone; each `when isMainModule` is its own CLI
(`build/harness`, `build/unit`, ...).

## Smoke test (CUDA preferred, CPU fallback)

Fast single-shot backend check (no agent loop): loads the model, generates a
short reply, reports PASS/FAIL + wall time.

```bash
devenv shell scripts/smoke_test.sh
# cuda  -> --backend cuda (PASS, ~4s) if NVIDIA GPU available
# cpu   -> --backend cpu (PASS, ~7s) as fallback
#
# Priority: CUDA if nvidia-smi detects GPU, otherwise CPU.
```

The harness's `--smoke --backend <kind> --prompt "..." --max-tokens n` single-shot
mode also benchmarks a backend directly (an explicit flag, not env vars).

```bash
# online (real model):
nim c --path:src -o:build/harness src/harness.nim
# offline (stub generator, no rwkv.cpp):
nim c --path:src -d:harnessOffline -o:build/unit src/unit.nim
```

Run the harness with the rwkv libs on the loader path:

```bash
LD_LIBRARY_PATH="rwkv.cpp:rwkv.cpp/ggml/src:$LD_LIBRARY_PATH" ./build/harness
```

## Backend Selection (RFC 7500)

Runtime backend is selected in one controlled place (`src/rwkv.nim`). Priority,
most-specific first:
1. Explicit `--backend` flag (CLI arg, same convention as `generate.nim`)
2. Config file: `nimo.json` → `"backend"` / `"lib"`
3. Compile-time default: `-d:rwkvDefaultBackend=cuda`
4. Backend modules (`src/rwkv/backend/cpu.nim`, `src/rwkv/backend/cuda.nim`) — lowest authority

That's the whole precedence — no more layers above it. (Env vars are fine when
they earn their place; they are simply not needed here, so the core path stays
config + flags.)

Switch point: `selectBackend(cfg)` → `bindBackend(libPath)` (one dlopen per session).

Per-backend GPU policy:
| backend | GPU probe | gpuLayers |
|---------|-----------|----------|
| `cpu`   | skip      | 0        |
| `cuda`  | required  | clamped  |

### CLI generate command

```bash
# Direct binary (CUDA if available, CPU fallback)
./build/generate --backend cuda --max-length 20 "prompt"
./build/generate --backend cpu --max-length 20 "prompt"

# Via harness dispatcher
./build/harness generate --backend cuda --max-length 20 "prompt"
```

### Measured performance (8 tokens, this machine)

| Backend | Time      | Notes |
|---------|-----------|-------|
| CPU     | ~15s      | OpenMP, no GPU |
| CUDA    | ~1s       | RTX 2050 (may fail if GPU state is bad) |

Note: CUDA may fail with `CUDA driver is a stub library` on this hybrid-
graphics laptop when the NVIDIA GPU is in a suspended state. Use `cpu`
as fallback. See `src/gpu.nim` for the probe logic.

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
  "model": "models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin",
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
- `devenv.nix` / `devenv.yaml` — dev env (allowUnfree is set in
  `devenv.yaml`; CUDA toolkit via `cudaPackages`).

## Conventions

- RFC-first: behavior is specified in `rfc/` (4-digit numbering, e.g. 3000-pipeline,
  9300-eval). Read the relevant RFC before changing behavior.
- Session JSONL must stay **one JSON object per line** (compact `$j`, not `pretty`).
- Don't break `-d:harnessOffline` builds — the eval suite depends on it.
- Keep tool handlers deterministic; model output is the only non-determinism.
- Agent work should leave the unit test suite green: `devenv shell unit`.

## Onboarding — Core Philosophy

> Nimo is a deterministic program wrapping a non-deterministic model. The coherence
> lives in the program and baked states, not in the model's attention or weights.
> The goal is to do with a 2.9B model what 100B models do with millions in fine-tuning.

### Design principles

1. **Explicit over implicit.** No fallbacks unless explicitly allowed. If a backend
   isn't available, error. If a model doesn't match `--quant`, error. One path,
   clear failures.
2. **Config > flags > nothing.** Single source of truth: `nimo.json`. Above it,
   `--backend` is the one override. Env vars are intentionally absent — they add
   hidden paths and hunting bugs.
3. **Low cognitive load.** We aren't in the 90s. Natural language is the interface.
   `nimo new "create a story about X"` not `nimo new story "X"`. Users should not
   need a manual. Developers should not need to read all files to change one thing.
4. **Tests enable fearless change.** Unit tests mock the model (precanned responses,
   no model loaded). Evals test the model's behavior in controlled environments
   (model is a black box). Know your confidence range and manage it.
5. **Git commit regularly.** Small, focused commits. The test suite is the safety net.
6. **Code should be elegant.** Nim templates and macros are tools, not curiosities.
   If something is repeated, abstract it. If a file does too much, split it.

### Architecture beliefs

- **Session = history + workspace reference.** No separate `goal`. No `activePlan`
  as a first-class concept — plan is part of the message chain.
- **Model backend is input, token stream is output.** Functional contract:
  `backend + workspace + context/state + prefill → token+event stream`.
- **gpuLayers from model + GPU, not default.** No hardcoded layer counts.
- **Pipeline steps are normal tool calls.** Injected into the session like any
  other message. Interruptible and resumible at any point.
- **Session history includes:** which model was used per turn, bake state per
  message, workspace switches. Everything traceable.
- **User sees streaming progress.** `creating plan` → plan items with checkmarks,
  actual generation visible per step. Never wait in silence.

### Where to look

- **RFCs** (`rfc/`): the intent. 4-digit numbers attach meaning (thousands = category,
  hundreds = sub-domain, tens+ones = exact aspect). Example-driven, not speculative.
- **Git history**: the evolution. How and why things changed.
- **Pi sessions** (`~/.pi/agent/sessions/--home-kit-dev-nimo--/`): the reasoning.
  Ephemeral session artifacts (plan/, analysis/, critique/) live here, not in the repo.
- **Docs** (`docs/`): end-user facing explanation.

### Message format

Each message in the session JSONL is one of:
- `user` — the user's input
- `think` — model reasoning (optional, between user and response)
- `text` — model's text response
- `tool_call` + `tool_result` — paired, the tool call and its output
- `system` — immutable operational rules

The flow: `user → (think) → text|tool_call → tool_result → user → ...`

### The RFC numbering scheme

| Thousand | Category |
|----------|----------|
| 0 | Meta (index, vision) |
| 1 | Core — Session & Messages |
| 2 | CLI — User Interface |
| 3 | Pipeline — Execution & Tools |
| 4 | Config — Settings |
| 5 | Workspace — Project Isolation |
| 6 | Architecture — Source Structure |
| 7 | Environment — Build & Runtime |
| 8 | Model — RWKV & Quantization |
| 9 | Infrastructure — Logging, Eval, Test |
| 9500+ | Speculative research (clearly marked) |

## Model Evals (RFC 9300)

`src/model_evals.nim` — Black-box model probes. Two families:
1. **Planner compilation** (offline, deterministic) — the default
2. **Scored state_bake** (online, real model) — model-as-judge evals

### Model-as-Judge Evals

The model itself is the judge. We bake a second state (`JudgeSystemPrompt`)
on the same loaded model, then ask it to score generated samples on metrics.

**Critical finding (RTX 2050, 2.9B model):**
- The 2.9B model **cannot reliably output just a number** regardless of:
  - Prompt format (instruction, few-shot, delimited)
  - Examples with/without `\x00` separators
  - Temperature (0.1-0.7)
  - State-baking technique
- Failure modes: echoes prompt, echoes examples, hallucinates, outputs "User"/"Bot"
- Success rate: ~10-20% of asks produce a parseable number
- The model-as-judge approach works mechanically but the small model is a weak judge

**Working approach:**
- Bake judge state with clear Criteria/Sample/Score/Explanation pattern
- Repeat "You are a judge. Output only a number 0-10." for EACH example
- Use `\x00` between examples to separate them
- Metrics should explain HOW scoring works (not just what to look for)
- Log all judge asks to `.nimo/judge-asks.jsonl` for diagnosis
- Accept ~40-80% unparseable rate and report it

```bash
nim c -o:build/model_evals src/model_evals.nim
./build/model_evals --scored --trials 1 --seed 42
```

### State-Bake Soundness

`src/test_state_bake.nim` — 4 deterministic checks on tiny model:
- Load tiny deterministic model
- Checkpoint == continue (bitwise logits)
- Cache file size matches state
- Save/load round-trips byte-for-byte

```bash
nimble state_bake_test
```

**Key insight:** State-bake works correctly (bitwise sound). The problem is
the model's inability to follow out-of-distribution instructions, not the
baking mechanism.
