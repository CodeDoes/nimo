# AGENTS.md — nimo

AI harness for local RWKV-7 inference (Nim). Deterministic harness wrapping a
non-deterministic model: `user -> pipeline -> chat/tool call -> answer`.
Sessions follow the pi-agent JSONL message-tree format (parentId chains).

## Project overview

- **Nim 2.2.10** app; model inference via `rwkv.cpp` (C/C++ backend, dlopen'd `librwkv.so`).
- Model: `models/rwkv7-g1i-2.9b-20260729-ctx16384-f16.bin` (converted from
  `~/Documents/models/rwkv7-g1i_preview5031-2.9b-20260729-ctx16384.pth`, FP16).
  Vocab: `rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt`.
- GPU: NVIDIA GeForce RTX 2050 (Ampere, sm_86, 4 GB) on a hybrid-graphics laptop
  (AMD Vega is boot VGA).

## Commands (run inside `devenv shell`)

```bash
devenv shell                 # enter dev env (nim, cmake, CUDA toolkit, python+torch)
devenv shell build-cuda      # rebuild rwkv.cpp with CUDA (MULTI-ARCH: 86;80;75;89 — slow!)
devenv shell build-vulkan    # rebuild rwkv.cpp with Vulkan/CLBlast
devenv shell eval            # nimble task: run offline evals (no model needed)
devenv shell build-all       # nimble build
```

Builds go to `build/`. Example commands in `src/` are compiled with:

```bash
# online (real model):
nim c --path:src -o:build/harness src/harness_main.nim
# offline (stub generator, no rwkv.cpp):
nim c --path:src -d:harnessOffline -o:build/evals src/evals.nim
```

Run the harness with the rwkv libs on the loader path:

```bash
LD_LIBRARY_PATH="rwkv.cpp:rwkv.cpp/ggml/src:rwkv.cpp/ggml/src/ggml-cuda:$LD_LIBRARY_PATH" ./build/harness
```

## GPU: verify before trusting it

The GPU often reports `pstate: [GPU requires reset]` (seen after driver installs
or suspend). Check first:

```bash
nvidia-smi --query-gpu=name,pstate,utilization.gpu,memory.used --format=csv
```

- Healthy: a real pstate (`P0`/`P8`) and utilization numbers.
- Broken: `[GPU requires reset]` / all `N/A` — CUDA init fails with
  `no CUDA-capable device is detected` even though nvidia-smi lists the card.

Fix requires root: reboot, or
`sudo modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia && sudo modprobe nvidia`.
Laptop GPUs don't support `nvidia-smi --gpu-reset`.

To rebuild CUDA fast for THIS machine only (sm_86), do NOT use `build-cuda`
(compiles 4 archs): configure with just `86`:

```bash
cd rwkv.cpp && rm -rf CMakeCache.txt CMakeFiles
cmake . -DRWKV_CUBLAS=ON -DCMAKE_CUDA_ARCHITECTURES="86" -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

## Model conversion gotchas

- `.pth` -> GGML `.bin`: `python3 rwkv.cpp/python/convert_pytorch_to_ggml.py <src.pth> <out.bin> FP16`.
- The nix python's numpy is broken (`undefined symbol: zgesv_`) — preload OpenBLAS:
  `LD_PRELOAD=/nix/store/*openblas*/lib/libopenblas.so python3 ...`
  (glob may match several; any works).
- torch 2.12.0 lives in the devenv shell; the bare `python3` outside it may not import torch.

## Evals

`src/evals.nim` — 16 checks, offline (scripted `genStub`, no model):

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
  `-d:harnessOffline` strips the RWKV backend (evals run without rwkv.cpp).
- `src/harness.nim` — agent loop + tool parsing + CLI.
- `src/pipeline.nim` — `run_pipeline` tool: steps, target files, state in `.nimo/`.
- `src/session.nim` — low-level RWKV session (real generation).
- `src/config.nim` — model/vocab paths + generation defaults.
- `devenv.nix` / `devenv.yaml` / `flake.nix` — dev env (allowUnfree is set in
  `devenv.yaml`; CUDA toolkit via `cudaPackages`).

## Conventions

- RFC-first: behavior is specified in `rfc/` (4-digit numbering, e.g. 3000-pipeline,
  9300-eval). Read the relevant RFC before changing behavior.
- Session JSONL must stay **one JSON object per line** (compact `$j`, not `pretty`).
- Don't break `-d:harnessOffline` builds — the eval suite depends on it.
- Keep tool handlers deterministic; model output is the only non-determinism.
- Agent work should leave evals green: `devenv shell eval`.
