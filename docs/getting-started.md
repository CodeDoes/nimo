# Getting Started

## What you need

- A Linux machine (the code assumes Linux paths and libraries).
- The RWKV model file (see below).
- Nim 2.x and the build tools (`devenv shell` provides them).

## 1. Build the tools

```bash
devenv shell build-all
```

This compiles everything via `nimble build_all`. The main entry point is `nimble run nimo`.

## 2. Get a model

You need a GGML-format model file. Two common cases:

**Already have a quantized model** (recommended, e.g. the Q4_K file):

```bash
devenv shell nimo generate --backend cuda --model models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin --prompt "Hello" --max-length 10
```

**Have a raw FP16 model** — shrink it first:

```bash
devenv shell nimo quantize models/raw-model-f16.bin Q4_K models/model-q4k.bin
```

Quantization turns a ~5.9 GB file into ~2.2 GB (Q4_K), which fits in the 4 GB
GPU. The process reads the model header, checks it's raw (not already
quantized), runs the quantizer, and reports the new size.

## 3. Run your first commands

**One-shot generation:**

```bash
devenv shell nimo generate --backend cuda --model models/model-q4k.bin --prompt "Write a haiku about rain" --max-length 40
```

**Interactive chat:**

```bash
devenv shell nimo chat --backend cuda models/model-q4k.bin
# type /quit to exit, /reset to start over
```

**The harness (tool calling):**

```bash
devenv shell nimo harness --backend cuda --model models/model-q4k.bin
```

The harness gives the model access to a `run_pipeline` tool. Ask it to "write a
poem about roses" and watch it call the tool, get the result, and answer you.

## 4. Work in a workspace

Workspaces keep projects separate. Create one, then check its status:

```bash
devenv shell nimo workspace create my_story
devenv shell nimo workspace use my_story
devenv shell nimo workspace status
```

A workspace contains `wiki/`, `chapters/`, `sessions/`, and `.nimo/` folders,
plus a `config.toml` and `outline.md` you can edit.

## 5. Verify everything works

```bash
devenv shell nimo unit
```

This runs the offline self-test suite (34 checks) — no model needed. It tests
tool-call parsing, session saving, cache logic, chapter validation, memory
search, and more. Everything should report PASS.

## 6. Spawn a Jules coding agent

`nimble run jules` is a thin CLI for the [Jules](https://jules.google.com) codeling
agent API — spawn a session on a GitHub repo and watch it work:

```bash
# validate the API key (masked; resolved from $JULES_API_KEY or .env)
nimble run jules check

# create a session that auto-opens a PR, and queue it locally
nimble run jules spawn "CodeDoes/nimo" "improve the unit suite" --pr

# see queued jobs (icon + id + PR when ready)
nimble run jules queue

# poll the most recent queued session until it finishes, streaming activity
nimble run jules watch
```

Other commands: `status <id>`, `activities <id>`, `prs`, `sessions`,
`send <id> "<msg>"`, `approve <id>`, `archive-all`. The API key is never
printed; spawned jobs are recorded in `./.jules.json`.

## Backend tips

- `--backend cuda` needs a working NVIDIA GPU. If it fails, the GPU probe
  prints the reason and how to fix it.
- `--backend vulkan` uses the AMD/other Vulkan driver path.
- You can pick the backend once in `nimo.json` (`"backend": "cuda"`) so you
  don't pass `--backend` every time.
