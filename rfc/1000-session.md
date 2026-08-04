# 1000 — Session

The conversation container. **Status: RE-SCOPED (planned).** `src/session_manager.nim`
currently carries model/tokenizer/state + tool registry and the CLI exposes
content-typed verbs (`chat`, `story`, `pipeline`). The target shape below makes
a Session **thin**: it is the history plus references — never the model, never
a content type.

## What a session is

A session is the unit of work you perceive: start it with a goal, watch it run
a plan against a workspace, pause/resume/branch, save and reopen. In data
space it is deliberately small:

```
Session (persisted, one per "conversation on a workspace")
  id             "sess_20260729..."
  goal           the natural-language intent   ("create a story about a lighthouse")
  history        the message tree (JSONL) — the conversation
  workspaceRef   which workspace is mounted (path/id)
  activePlanRef  optional — the program in flight (.nimo/programs/<id>.json)
  modelRef       the model file used for the last generation (path + signature)
  createdAt / updatedAt
```

### What deliberately does NOT live on a Session

| Thing | Where it lives instead | Why |
|-------|------------------------|-----|
| model / tokenizer / model state | workspace caches (state cache keyed by context, model cache) | session is conversation, not compute |
| tool registry | built per-session from the workspace + engine | reached by capability/interface (principle D) |
| content type ("story", "memory", …) | nowhere — chosen by the orchestrator from the goal | the user never picks machinery |
| the plan itself | `.nimo/programs/<id>.json` in the workspace | shareable, resume-able, separate from the conversation |

A session is **not** a "story session" or "chat session." It is a goal, a
conversation, and a mounted workspace — the plan runs in the workspace, the
model state is a cache, and the content type is inferred.

## Provenance: what produced what

Sessions are reproducible: they record which model and which baked skill state
turned each input into each output.

- **Session-level `modelRef`** — the model file used for the last generation
  (path + signature, the same signature that keys the model/state caches).
  Reopening a session reloads this model, so `continue` keeps the same
  behavior.
- **Per-message `modelRef` + `bakeRef`** — each generated message records the
  model that produced it and the baked state (skill) that was active at the
  time, referenced by its cache key (e.g. `planner`, `output:chapter`), never
  by a state blob.

The header and each message carry these refs (optional fields in the JSONL).
`bakeRef` is the auditable link for state-tuning: given a message you can name
the skill that shaped it.

## History — the message tree

The history is the pi-agent JSONL message tree (one JSON object per line):

1. Header line: `{"type":"session","id":...,"goal":...,"workspaceRef":...,"activePlanRef":...,"modelRef":...}`.
2. One line per message: user, assistant (text/toolCall), toolResult —
   linked by `parentId`, terminated by a `stopReason` (`stop` | `toolUse`).
   Generated messages also carry `modelRef` and `bakeRef` (which model +
   which baked skill state produced them).

A typical chain:

```
msg0 (user, goal)
  └─ msg1 (assistant, toolCall: Extract memory)
       └─ msg2 (toolResult)
            └─ msg3 (assistant, text: ...)   <- partial prose / report
```

The tree IS the observable record of the run. Saving is one object per line.
## How the user perceives it

| Context | The session is |
|---------|----------------|
| Running app (TUI) | the thing you're working in right now: history + plan progress + streaming tokens + files it writes into the mounted workspace; pause/resume/branch/save |
| CLI | a named, resumable container: `new <goal>` opens one, `list`/`open`/`continue`/`run` manage it (see 2000-cli) |
| Not running | just the persisted `{history, workspaceRef, activePlanRef}` above |

## See Also

- [1100-message-format.md](1100-message-format.md) — the history's message format
- [3500-plan-format.md](3500-plan-format.md) — the plan artifact it points at
- [2000-cli.md](2000-cli.md) — session verbs (`new`/`open`/`continue`/`run`)
- [3600-engine.md](3600-engine.md) — the executor that runs the plan