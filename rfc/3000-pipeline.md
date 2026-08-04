# 3000 — Pipeline

Intent → plan → execute. **Status: superseded design — the single-step
`run_pipeline` MVP (`src/pipeline.nim`) is being replaced by plan-based
execution per [3500-plan-format.md](3500-plan-format.md).**

> Today `src/pipeline.nim` still has the MVP: it turns an intent into **one**
> generate step (plus dormant `summarizeStep`/`extractStep` helpers) and reports
> the JSON pipeline id. The goal below is the target behavior.

## What it is

When a user message has a goal, the planner compiles it into a **plan** — a
flat list of pointed steps. `run_pipeline` / the engine executes that plan
**deterministically**, streaming every token, checkpointing for resume.

The old single-step behavior (`intent → one generate → output.txt`) is a stub;
the intended behavior uses the real step vocabulary:

```
(template) story:
  generate  outline                               → outline.md
  extract   characters                            → characters[]
  loop c in characters:
      extract outline events relevant to c
      generate wiki entry                          → wiki/{c}.md
  loop ch in outline.chapters:
      extract outline segment for ch
      extract wiki slice for ch
      generate chapter                             → chapters/{ch}.md
  report   story finished
```

## How a plan executes (step by step)

1. **Interpret** — planner emits a parseable plan (steps + filters).
2. **Shuffle/validate** — the plan is parsed; a bad plan is rejected (parse
   error, not weird prose).
3. **Execute** — the engine walks the steps:
   - `Extract` → pull the focused slice (model or memory lookup)
   - `Summarize` → condense
   - `Generate` → output-state, **streaming** through a sink
   - `Validate` → deterministic gate
   - `Write` → file output
   - `Loop` → splice a sub-plan per extracted item
   - `Report` → checkpoint
4. **Save** — the plan + cursor + checkpoints are persisted (resumable).
5. **Report** — final natural-text answer streams live.

## The manifest

Each plan is saved as a JSON manifest (`.nimo/programs/<id>.json` or under a
workspace) with the plan id, goal, cursor, step statuses, and outputs.

## Config interaction

`Generate` steps use generation defaults from config (temperature, topP, max
tokens) — see [4000-config.md](4000-config.md).

## See Also

- [3500-plan-format.md](3500-plan-format.md) — the plan artifact
- [3600-engine.md](3600-engine.md) — the executor
- [3400-agent.md](3400-agent.md) — the orchestration loop
- [1100-message-format.md](1100-message-format.md) — planner emission format