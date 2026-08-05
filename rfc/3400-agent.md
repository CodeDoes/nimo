# 3400 — Agent

The orchestration loop. **Status: superseded design — the improvisation loop
(`src/harness.nim`) is being replaced by planner → plan → engine.**

> This RFC documents the **intended** architecture. Today `src/harness.nim`
> still contains the old loop where the model improvises `[tool]` calls inside
> its reply; that behavior contradicts the design and is being removed. Code in
> transition is tracked in git history.

## What it is now

The user is **not** answered by an improviser. Their message is **compiled**:

```
user message
  → planner: interpret(message) → PLAN (data)      (src/orchestrator.nim, planned)
  → engine:  run(plan, session, sink)              (src/engine.nim, planned)
       each step: extract / summarize / generate / validate / write / report
       streams tokens; checkpoints for resume; fans out over data-driven loops
  → reporter: stream results && final report
```

### 1. Interpret

The planner state takes the fuzzy message and emits a **flat list of pointed
steps** (machine-readable — reuses the `[tool]`/JSON emission format, see
[1100-message-format.md](1100-message-format.md)). The plan is **data** per
[3500-plan-format.md](3500-plan-format.md).

### 2. Execute

The engine walks the plan deterministically. Each `Generate` step streams every
token through a sink. `Loop` steps splice sub-steps from extracted lists.
Failures gate through `Validate`. See [3600-engine.md](3600-engine.md).

### 3. Report

`Report` steps surface progress; the user sees live streaming text plus
`▶/✔` step events. The final output is a natural-text answer.

## Why not the old improvisation loop

The old model — "generate a reply, parse it for `[tool]` calls, feed results
back, repeat ≤8×" — made the *model* the orchestrator, improvising tool calls
mid-prose. That:

- mixes "thinking about the plan" and "producing output" in one state (violates
  *one kind at a time*),
- is fragile and non-deterministic (needs a re-parse every iteration),
- has no plan artifact to resume or observe.

The new model keeps the reasoning in the **plan**, the model as a focused,
streaming executor.

## Session bookkeeping

The session message tree still records user → steps → results → answer (see
[1000-session.md](1000-session.md)); it now also records the running plan and
checkpoints.

## Offline mode

With `-d:harnessOffline`, no model is loaded: the session uses a scripted
generator (`genStub`) so interpretation, execution, and evals run without
rwkv.cpp.

## See Also

- [3500-plan-format.md](3500-plan-format.md) — the plan artifact
- [3600-engine.md](3600-engine.md) — the streaming executor
- [3000-pipeline.md](3000-pipeline.md) — plumbing intent → steps
- [1000-session.md](1000-session.md) — the message tree