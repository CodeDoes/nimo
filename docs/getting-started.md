# Getting Started

## What you need

- A Linux machine (the code assumes Linux paths and libraries).
- The RWKV model file (see below).
- Nim 2.x and the build tools (`devenv shell` provides them).

## 1. Build the tools

```bash
devenv shell build-all
```

This compiles everything into `build/`. The main entry point is `build/nimo`.

## 2. Get a model

You need a GGML-format model file. Two common cases:

**Already have a quantized model** (recommended, e.g. the Q4_K file):

```bash
./build/nimo generate --backend cuda --model models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin --prompt "Hello" --max-length 10
```

**Have a raw FP16 model** — shrink it first:

```bash
./build/nimo quantize models/raw-model-f16.bin Q4_K models/model-q4k.bin
```

Quantization turns a ~5.9 GB file into ~2.2 GB (Q4_K), which fits in the 4 GB
GPU. The process reads the model header, checks it's raw (not already
quantized), runs the quantizer, and reports the new size.

## 3. Run your first commands

**One-shot generation:**

```bash
./build/nimo generate --backend cuda --model models/model-q4k.bin --prompt "Write a haiku about rain" --max-length 40
```

**Interactive chat:**

```bash
./build/nimo chat --backend cuda models/model-q4k.bin
# type /quit to exit, /reset to start over
```

**The harness (tool calling):**

```bash
./build/nimo harness --backend cuda models/model-q4k.bin
```

The harness gives the model access to a `run_pipeline` tool. Ask it to "write a
poem about roses" and watch it call the tool, get the result, and answer you.

## 4. Work in a workspace

Workspaces keep projects separate. Create one, then check its status:

```bash
./build/nimo workspace create my_story
./build/nimo workspace use my_story
./build/nimo workspace status
```

A workspace contains `wiki/`, `chapters/`, `sessions/`, and `.nimo/` folders,
plus a `config.toml` and `outline.md` you can edit.

## 5. Verify everything works

```bash
./build/nimo unit
```

This runs the offline self-test suite (34 checks) — no model needed. It tests
tool-call parsing, session saving, cache logic, chapter validation, memory
search, and more. Everything should report PASS.

## Backend tips

- `--backend cuda` needs a working NVIDIA GPU. If it fails, the GPU probe
  prints the reason and how to fix it.
- `--backend cpu` always works but is slower (~15s vs ~1s for 8 tokens).
- `--backend vulkan` uses the AMD/other Vulkan driver path.
- You can pick the backend once in `nimo.json` (`"backend": "cuda"`) so you
  don't pass `--backend` every time.
