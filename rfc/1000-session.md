# 1000 — Session

The conversation container. **Status: RE-SCOPED (planned).** `src/session_manager.nim`
currently carries model/tokenizer/state + tool registry on the Session and the
CLI exposes content-typed verbs (`chat`, `story`, `pipeline`). The target
shape below makes a Session **thin**: it is the history plus a workspace
reference. Everything else — messages, the plan, model provenance — is
*events in the history*, never fields on the session.

## What a session is

A session is the unit of work you perceive: start it with a goal, watch it run
a plan against a workspace, pause/resume/branch, save and reopen. In data
space it is deliberately small:

```
Session (persisted, one per "conversation on a workspace")
  id             "sess_20260729..."
  goal           the natural-language intent   ("create a story about a lighthouse")
  history        the message tree (JSONL) — messages + plan + model provenance
  workspaceRef   which workspace is mounted (path/id)
  createdAt / updatedAt
```

### What deliberately does NOT live on a session

| Thing | Where it lives instead | Why |
|-------|------------------------|-----|
| model / tokenizer / model state | workspace caches (state cache keyed by context, model cache) | session is conversation, not compute |
| tool registry | built per-session from the workspace + engine | reached by capability/interface (principle D) |
| content type ("story", "memory", …) | nowhere — chosen by the orchestrator from the goal | the user never picks machinery |
| the plan | **in the history** — a `plan` node whose children are step executions | the plan is data the engine writes into the tree |
| the model used | **in the history** — a `model` event when the session starts, a `model` event again on every switch | provenance is observable, replayed from the tree |

A session is **not** a "story session" or "chat session." It is a goal, a
conversation, and a mounted workspace — the model state is a cache, and the
content type is inferred.

## Provenance: what produced what

Sessions are reproducible, and the history is the record of it.

- **Model usage** — events in the history. When an agent response starts, a
  `model` event records the bound model (path + signature). If the model
  changes mid-session, another `model` event marks the switch. You can read the
  whole session and reconstruct which model every message came from.
- **Baked skill per message** — each generated message carries a `bakeRef`: the
  baked state (skill) that was active when it was written, referenced by its
  cache key (e.g. `planner`, `output:chapter`), never by a state blob.

`bakeRef` is the auditable link for state-tuning: given a message you can name
the skill that shaped it. Model events let you name the model too.

## History — the message tree

The history is the pi-agent JSONL message tree (one JSON object per line):

1. Header line: `{"type":"session","id":...,"goal":...,"workspaceRef":...}`.
2. One line per event/message: `model` (bound/switched), `plan` (the compiled
   program), `user`, `assistant` (text/toolCall), `toolResult` — linked by
   `parentId`, terminated by a `stopReason` (`stop` | `toolUse`). Generated
   messages carry `bakeRef`; model usage is the `model` events.

A typical chain:

```
e0 (model: bound to rwkv7-...q4k.bin, sig ...)
e1 (plan: [Extract memory -> Generate chapter -> Validate])
e2 (user, goal)
  └─ e3 (assistant, toolCall: Extract memory, bakeRef: planner)
       └─ e4 (toolResult)
            └─ e5 (assistant, text: ..., bakeRef: output:chapter)
```

The tree IS the observable record of the run. Saving is one object per line.
Resume reads the history: the latest `plan` node (with its checkpoint) is the
cursor from which the engine continues; the latest `model` event names the
model to reload.

## How the user perceives it

| Context | The session is |
|---------|----------------|
| Running app (TUI) | the thing you're working in right now: history + plan progress + streaming tokens + files it writes into the mounted workspace; pause/resume/branch/save |
| CLI | a named, resumable container: `new <goal>` opens one, `list`/`open`/`continue`/`run` manage it (see 2000-cli) |
| Not running | just the persisted `{history, workspaceRef}` above |

## See Also

- [1100-message-format.md](1100-message-format.md) — the history's event format
- [3500-plan-format.md](3500-plan-format.md) — the plan as a node in the history
- [2000-cli.md](2000-cli.md) — session verbs (`new`/`open`/`continue`/`run`)
- [3600-engine.md](3600-engine.md) — the executor that runs the plan