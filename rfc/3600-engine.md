# 3600 — Engine

The engine is the executor that takes a plan and runs it — **forever if
needed** — streaming every token, checkpointing for resume, and allowing
interruption. This RFC defines its contract. **Status: design reference**.

## What an engine is

A user message is **compiled** into an engine:

```nim
compile(userMessage) -> Engine:
  plan  = planner.emit(userMessage)      # flat list of pointed steps
  state = bake(userMessage's context)    # the mode/pattern the engine holds
  return Engine(plan, state, cursor = 0)
```

An engine is not a fixed script — it is a persistent loop that consumes new
input, re-extracts, and continues. It "runs infinitely" because each cycle is
fresh pointed work on a focused slice.

## The non-negotiable: streaming

The moment a token is sampled, it must be visible. There is no buffering at the
model boundary and no "waiting while the model generates."

```nim
type TokenSink = proc(text: string)        # called once per token, immediately

proc generate(session, prompt, sink: TokenSink, stop = no):
  for token in sampleLoop(...):
    sink(session.tok.decode(token))        # emit NOW
    if shouldStop: break
```

Every layer picks its own sink (terminal, TUI, log file — or a `tee` of them).

## The run loop (infinite)

```nim
proc Engine.run(sink):
  while true:
    step = plan.advance()
    case step:
      of Extract:  data += extract(step)                  # feeds loops / later steps
      of Summarize: data += summarize(step)                # condense
      of Generate: step.outputState.generate(sink)          # STREAMING tokens
      of Validate: gate(step.text)                          # deterministic, stops drift
      of Write:    writeFacility(step.path, step.output)    # deterministic
      of Loop:     plan.splice(subPlan(items, step.build))  # data-driven fan-out
      of Report:   checkpoint(step.title)                   # step-level event
    cursor++
    checkpoint.save()                        # always resumable

```

The loop produces two **observable** layers:

```
token-level: every sample decodes straight to the sink (never wait)
step-level:  "▶ extract characters" → [streaming tokens] → "✔ extract characters (2.1s)"
```

## Checkpoint / resume contract

A checkpoint is the (plan, cursor, state, artifacts) trio. It supports:

- **Resume** — reload plan + cursor + state, continue from exactly there.
  A resuming step uses its **prefill** (RFC 3500): the engine feeds the step's
  already-produced tail into `generate` so the generation continues instead of
  restarting.
- **Re-plan** — after pause, run a light planner pass over the remaining steps
  given what happened since the pause ("chapter 3 failed validation" → adjust).
- **Interrupt** — stop the sink at any time (keypress / signal), snapshot the
  checkpoint, return control. Nothing is lost.

### Why resume is meaningful

It isn't "continue from token X" — it's *"continue the plan from step N,"*
optionally with a re-plan pass over the remainder. Because the plan is data,
interruption and repair are cheap.

## Re-aiming an engine

A new user message re-fires the loop:

```nim
Engine.aim(newMessage):
  plan = planner.emit(newMessage)      # fresh plan for the new goal
  state reset / re-baked as needed
  run(sink)                             # continues, streaming
```

The engine is a living vehicle: observe it, pause it, repoint it.

## Mapping to the existing code

The pieces already present, and what changes:

| Existing code | Today | Becomes |
|---------------|-------|---------|
| `session_manager.generateTurnStream` | decodes a reply and calls `TokenSink` once per token | shared streaming model boundary |
| `generate.nim` | already streams per token (`stdout.write` + `flushFile`) | the canonical streaming example |
| `chat.nim` / `harness.nim` | forward the shared sink to stdout and flush | streams while each reply/step is generated |
| `pipeline.nim` / `story.nim` | fixed/hardcoded step flows | driven by a plan (`Step` vocabulary) |
| `session_manager.nim` | message tree | also records the running plan + checkpoints |
| `memory.nim` / `fiaas.nim` | exist, not wired | the `Extract`/`lookupMemory` tools |

## See also

- `rfc/3500-plan-format.md` — the plan the engine walks
- `docs/architecture.md` — design principles (streaming, engine, pointed tools)