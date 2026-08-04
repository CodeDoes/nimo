# Plan: Formalize the Engine Design

## Status: COMPLETE ✓

## Goal

Formalize the conceptual design we converged on into markdown reference docs so
the runtime (`program.nim`) can be built against them.

## Concepts captured

- **Planner = decomposer, not creator** — emits structure only (parseable plan)
- **Intelligence ≈ structure, not context length** — small model + program
- **State-tuning instead of weight-tuning** — baked states = cheap "skills"
  (two species: planner state → plans; output state → a sort of prose)
- **Pointed tools beat sub-planners** — extract/summarize/validate/write/lookup
- **One kind of thing at a time** — RWKV mixes/forgets heterogeneous content
- **Streaming is default** — never wait; every token visible instantly
- **Engine that runs forever** — compiled from a user message; resumable,
  interruptible, observable
- **Plan is data** — resumable/observable for free

## Files written

| File | Purpose |
|------|---------|
| `docs/architecture.md` | Design principles + system anatomy + engine concept |
| `rfc/3500-plan-format.md` | Step vocabulary (Extract/Generate/Validate/Loop/Write/Report), plan shape, example |
| `rfc/3600-engine.md` | TokenSink, infinite run loop, checkpoint/resume/interrupt contract |
| `rfc/0000-index.md` | index updated with 3500 + 3600 |
| `docs/index.md` | architecture added to guides |

## Next step

Build the runtime against the spec: `program.nim` (plan type + step types) and
the streaming executor (TokenSink), then wire `session.generateTurn` to stream.

## See also

- `rfc/3500-plan-format.md` — the plan artifact
- `rfc/3600-engine.md` — the streaming executor
- `docs/architecture.md` — the design principles