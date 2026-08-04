# 1000 — Session

The conversation container. **Status: RE-SCOPED (planned).** `src/session_manager.nim`
currently carries model/tokenizer/state + tool registry on the Session and the
CLI exposes content-typed verbs (`chat`, `story`, `pipeline`). The target
shape below makes a Session **thin**: it is just the history (plus an id).
Everything content-shaped — user goals, the plan, model and workspace usage —
is *events/messages in the history*, never fields on the session.

## What a session is

A session is a running conversation. You open one, keep talking to it (each
message may be a new goal, a re-aim, or a follow-up), watch it run plans, and
save/reopen it. In data space it is minimal:

```
Session (persisted, keyed by id in a central store)
  id          "sess_20260729..."
  history     the message tree (JSONL) — everything, in order
  createdAt / updatedAt
```

There is **no goal field**. A session has arbitrarily many user messages; the
first one (and any later one) states the current intent. Opening the session
shows the history; the latest user message is what you're working on.

Sessions live in a **central store** (keyed by id), not inside a workspace —
the workspace they use is part of the history, and a session may move between
workspaces over its life. Opening a session reads its history and mounts from
the latest `workspace` event.

### What deliberately does NOT live on a session

| Thing | Where it lives instead | Why |
|-------|------------------------|-----|
| the goal / intent | the latest user message in the history; many per session | sessions are conversations, not single intents |
| model / tokenizer / model state | workspace caches (state cache keyed by context, model cache) | session is conversation, not compute |
| tool registry | built per-session from the workspace + engine | reached by capability/interface (principle D) |
| content type ("story", "memory", …) | nowhere — chosen by the orchestrator from the goal | the user never picks machinery |
| the plan | **in the history** — a `plan` node whose children are step executions | the plan is data the engine writes into the tree |
| the model used | **in the history** — a `model` event when generation starts, another on every switch | provenance is observable, replayed from the tree |
| the workspace | **in the history** — a `workspace` event when the session starts, another on every switch | a session may move between workspaces; the mount is part of the run |

A session is **not** a "story session" or "chat session." It is a conversation;
the model state is a cache, and the content type is inferred per user message.

## Provenance: what produced what

Sessions are reproducible, and the history is the record of it.

- **Model usage** — events in the history. When an agent response starts, a
  `model` event records the bound model (path + signature). If the model
  changes mid-session, another `model` event marks the switch. Reading the
  tree reconstructs which model every message came from.
- **Baked skill per message** — each generated message carries a `bakeRef`: the
  baked state (skill) that was active when it was written, referenced by its
  cache key (e.g. `planner`, `output:chapter`), never by a state blob.

`bakeRef` is the auditable link for state-tuning: given a message you can name
the skill that shaped it. Model events let you name the model too.

## History — the message tree

The history is the pi-agent JSONL message tree (one JSON object per line):

1. Header line: `{"type":"session","id":...,"timestamp":...}`.
2. One line per event/message: `model` (bound/switched), `workspace`
   (mounted/switched), `plan` (the compiled program), `user` (a message — any
   one may restate the goal), `assistant` (text/toolCall), `toolResult` — linked
   by `parentId`, terminated by a `stopReason` (`stop` | `toolUse`). Generated
   messages carry `bakeRef`.

A typical chain:

```
e0 (workspace: mounted to ~/.ws/book-1)
e1 (model: bound to rwkv7-...q4k.bin, sig ...)
e2 (user, "create a story about a lighthouse")   <- the current intent
e3 (plan: [Extract memory -> Generate chapter -> Validate])
  └─ e4 (assistant, toolCall: Extract memory, bakeRef: planner)
       └─ e5 (toolResult)
            └─ e6 (assistant, text: ..., bakeRef: output:chapter)
e7 (user, "make the lighthouse keeper older")    <- a re-aim
  └─ e8 (plan: [Extract ... -> Regenerate ...])
```

If the model or workspace changes, another `model`/`workspace` event is
inserted at that point — so the tree always tells you which model and workspace
every message ran against.

The tree IS the observable record of the run. Saving is one object per line.
Resume reads the history: the latest `plan` node (with its checkpoint) is the
cursor from which the engine continues; the latest `model` and `workspace`
events name the model to reload and the workspace to re-mount.

## How the user perceives it

| Context | The session is |
|---------|----------------|
| Running app (TUI) | the thing you're working in right now: the running conversation + plan progress + streaming tokens + files it writes into the mounted workspace; pause/resume/branch/save |
| CLI | a named, resumable conversation: `new <goal>` opens one, `list`/`open`/`continue`/`run` manage it (see 2000-cli) |
| Not running | just the persisted `{history}` above |

## See Also

- [1100-message-format.md](1100-message-format.md) — the history's event format
- [3500-plan-format.md](3500-plan-format.md) — the plan as a node in the history
- [2000-cli.md](2000-cli.md) — session verbs (`new`/`open`/`continue`/`run`)
- [3600-engine.md](3600-engine.md) — the executor that runs the plan