# NIMO — End-User Documentation

NIMO is a local AI writing/inference tool built around the RWKV-7 model. You
talk to it, it answers, and it can run longer "pipelines" that produce stories,
notes, and reports — all stored in neat project folders called *workspaces*.

## What you can do

| You want to... | Use this |
|----------------|----------|
| Get a quick answer from the model | `nimo generate` |
| Have a back-and-forth conversation | `nimo chat` |
| Let the model call tools (pipeline) | `nimo harness` |
| Shrink a big model file | `nimo quantize` |
| Pre-compute a model state for fast start | `nimo bake` |
| Keep separate projects (story worlds) | `nimo workspace` |
| Write and check chapters of a story | `nimo story` |
| Show the plan for a goal | `nimo planner` |
| Create a session from a goal | `nimo new` |
| Execute a plan artifact | `nimo run` |
| Run the self-test suite | `nimo unit` |
| Run model behavior evals | `nimo model-eval` |

## The big picture (how a request flows)

1. **You type a command** — `nimo` reads it and hands it to the right tool.
2. **Settings are gathered** — from `nimo.json`, then environment variables.
3. **A backend is chosen** — CUDA (GPU), CPU, or Vulkan. The GPU is checked
   first so a broken card gives a clear message instead of a crash.
4. **The model loads** — from a quantized file, reusing a cached copy if one
   exists so you don't re-quantize every time.
5. **The request runs** — prompt → model → text, token by token.
6. **Tools run if needed** — the harness may ask the model to call `run_pipeline`.
7. **Everything is saved** — conversations, chapters, and reports are written
   to your workspace (and the `.nimo/` folder).

The detailed walk-through is in [how-it-works.md](how-it-works.md).

## Guides

- [Getting started](getting-started.md) — install, build, first commands
- [How it works](how-it-works.md) — the full request flow, step by step
- [Architecture](architecture.md) — the design principles (program, baked states, engine)
- [NIMO Engine](engine.md) — intent, planning, execution, and session management
- [Story writing](story-writing.md) — outline → chapters → validation → critique
- [Memory & notes](memory.md) — how the model remembers characters and facts

## Project layout

```
~/.ws/<name>/          your workspaces
  wiki/                character & world notes
  chapters/            story chapters (01_..., 02_...)
  sessions/            saved conversations
  .nimo/               model cache + state cache
  config.toml          per-workspace settings
  outline.md           the story outline

./.nimo/               app folder in the working directory
  state/  cache/  logs/  sessions/  pipelines/
```

See git history and RFCs for the implementation status
code modules behind all of this.
