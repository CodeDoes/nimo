# 0001 — Vision

NIMO is an AI Harness — deterministic software wrapping non-deterministic LLM
inference. The user message is **compiled into an engine**, not answered: an
engine is a resumable, interruptible, observable program that streams its work.

## Core Principles

1. **Planner, not improviser** — a planner state turns a fuzzy goal into a
   **plan (data)**. The model does NOT improvise tool calls while generating;
   it emits structure, and the machinery executes that structure deterministically.
2. **Pointed tools, not sub-planners** — tasks decompose by slicing information
   (`extract`, `summarize`) rather than recursively splitting the goal.
3. **One kind of thing at a time** — the model is never asked to multiplex
   heterogeneous content in one state; each step works a focused slice
   (see [docs/architecture.md](../docs/architecture.md)).
4. **State-tuning, not weight-tuning** — skills are **baked states** (planner
   state + output states), not gradient fine-tuning (see [8000-state-bake.md](8000-state-bake.md)).
5. **Streaming is default** — the moment a token is sampled it is visible; the
   user never waits while the model generates.
6. **Plan is data** — resumable, interruptible, observable, and safe to edit.
7. **Checkpoint / Resume** — save plan + cursor + state, continue from step N,
   optionally re-planning the remainder.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  User (CLI/TUI) — sees every token stream, every step ▶/✔  │
├─────────────────────────────────────────────────────────────┤
│  NIMO                                                       │
│  ├─ Planner   (learned, structure-only) → plan (data)       │
│  ├─ Engine / Executor (deterministic, streaming)            │
│  │    runs the plan forever, fans out over data-driven loops│
│  ├─ Pointed tools (extract, summarize, validate, lookup,    │
│  │                 write)                                   │
│  ├─ Output states (the only creative part, per sort)        │
│  ├─ Checkpoint / Resume / Interrupt                         │
│  └─ Session (message tree + running plan + checkpoints)     │
├─────────────────────────────────────────────────────────────┤
│  Model (RWKV-7, always small, always focused, streaming)    │
└─────────────────────────────────────────────────────────────┘
```

## Workload modes

Plans can be pre-compiled as **templates** for common goals, then executed by
the engine:

| Template | Steps (pointed tools) | Purpose |
|----------|-----------------------|---------|
| story    | outline → extract characters → per-character wiki → per-chapter (extract outline+wiki → generate) → validate → critique | long-form creative |
| memory   | extract → lookupMemory → remember | continuity |
| explain  | extract → summarize → generate | answer |

## Session format

JSONL message tree (see [1000-session.md](1000-session.md)), extended to record
the running plan and checkpoints.

## See Also

- [rfc/3500-plan-format.md](3500-plan-format.md) — the plan artifact
- [rfc/3600-engine.md](3600-engine.md) — the streaming executor
- [docs/architecture.md](../docs/architecture.md) — design principles
- [3000-pipeline.md](3000-pipeline.md) — intent → plan compilation