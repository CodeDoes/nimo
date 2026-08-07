# RFC 2111 — Unified Chat & the Command DSL

**Status:** design (supersedes the repl-only framing of RFC 2110)
**Category:** 2 — CLI / User Interface
**Author:** user + Agnes (design review)

## One turn starts, step by step: vocabulary

Two sizes of grain matter, and mixing them is the root of most confusion:

- **`turn`** — a complete, addressable exchange. A **user turn** (the input)
  or an **assistant turn** (the agent's full reply: plan → steps → final
  answer). A session is a sequence of turns.
- **`step`** (synonym: **`action`**) — an *atomic* action *inside* a turn:
  one `Generate`, one `tool_call`, a `validate`, a `write`, a step in a plan.
  Steps are the grain at which steering and interruption inject, never turns.

The practical rule: **a `turn` is conversational; a `step` is mechanical.**
The agent loops over steps; the conversation counts turns.

## The claim

The user-facing grammar and the plan grammar are **the same DSL**.

- `/`-prefixed lines a human types are **commands**.
- A **plan** is literally a sequence of those same commands (a scripted DSL).
- Therefore the **command dispatcher is the plan executor** — one interpreter.
  A plan the drone emits and a sequence a human types both run through the
  exact same code path.

> Consequence of the "coherence in the program" principle: a plan is **data
> you can read, edit, copy, and paste back** — and pasting a plan is just
> re-running commands through the same dispatcher. There is no second,
> private, machine-only plan format.

## `chat` is the single interactive entry

One command, one process, **two threads**:

- **Reader thread** owns stdin. Every line goes into a shared inbox. Typing is
  never blocked — the agent is busy, you can still type.
- **Agent thread** runs the turn loop over `engine.run` (the existing plan
  executor) and drains the inbox at safe points.

### State machine

```
idle ──send──▶ busy ──(turn completes)──▶ idle
  ▲              │
  └──queue───────┘   (deliver when idle → send-on-finish)
```

`busy` holds while an assistant turn is executing (any plan/tool/generation).
The loop drains the inbox **between steps**, never mid-step.

## Verbs: send / steer / queue / plan

- **send** — start a new **user turn**.

  Only meaningful when **idle**. (Bare input when idle defaults to this.)

- **steer** — inject a directive **between actions**.
  It does **not** interrupt the currently-forming step. The in-flight action
  (usually a `tool_call`) completes; the steer is applied at the next step
  boundary as clarification/redirection before the next action. Default for a
  bare line when the agent is **busy**.

- **queue** — hold text with a **delivery trigger** (a gate), then send when
  the gate opens:
  - **send-on-finish** — deliver when the session goes `idle`.
  - **send-on-action-completed** — deliver at the next step boundary
    (equivalent to a queued `steer`, just written ahead of time).

  The inbox is therefore not a single pile: each queued message carries its
  gate. `steer` is a message with gate = next-boundary; `queue` = a message
  with a gate you pick.

## Input dialect

- **Bare line** → agent mode.
  - idle → `send`
  - busy → `steer` (default; configurable)
- **`/`-prefixed line** → explicit verb ("repl mode"). Some verbs: `/send`,
  `/steer`, `/queue <gate>`, `/plan`, `/save`, `/story`, `/state`, `/ws`,
  `/help`, `/quit` …

### `plan` (not `planner`)

- `/plan <goal>` — the **agent** thinks and produces a plan **in the DSL**.
  Output is a copyable, editable plan artifact.
- Feed that plan back in (paste / `/run`) and it executes through the same
  dispatcher — the same path the drone's own turn uses. Deterministic,
  inspectable, resumable.

## Migration

- New `src/chat.nim` becomes the interactive entry.
- Old `repl.nim` and `chatCL` remain as **aliases** that open `chat` (zero-loss
  migration); drop them once the alias proves stable.
- RFC 2110's "one registry, two drivers" collapses: the registry is the DSL,
  and the drone vs. human distinction is only *who* types the commands.

## Rejected & clarified (from earlier confusion)

- `send` and `steer` are **not** aliases. They differ by *when* they act
  relative to the turn/tool boundary.
- `steer` is not a mid-token interrupt; it is a boundary injection.
- A bare message is still never implicitly a `tool` — but with threading, the
  receiver can *react* to input while busy (that's what a busy-`steer` is).
- Plans are not a separate binary format; `plan dsl ≡ command dsl`.

## Builds on

- [3500-plan-format.md](3500-plan-format.md) — the plan as a data workhorse
- [3600-engine.md](3600-engine.md) — the streaming executor (`engine.run`)
- [2110-repl.md](2110-repl.md) — the protocol it supersedes

## The action set: what the plan (and the chat) can do

The plan DSL is the command DSL. Every plan step is a command the user can
also type with `/`, and every command the user types is a step the plan can run.
This is the single grammar.

### Engine steps (the mechanical backbone)

These are the atomic actions the executor runs, one per step. Each is
invocable by the plan (and by the human via a matching command):

| DSL command | Engine kind | What it does | Needs model? |
|-------------|-------------|--------------|--------------|
| `/generate ...` or `/plan generate ...` | `skGenerate` | produce prose via the model (the only thinking step) | yes |
| `/extract <filter> from <source>` | `skExtract` | pull a focused slice from a source (model or memory lookup) | sometimes |nimo | `skExtract` | pull a focused slice from a source (model or memory lookup) | | sometimes |
| `/summarize <input> to <length>` | `skSummarize` | condense to essence | yes |
| `/validate <text>` | `skValidate` | deterministic gate: word count, paragraph count, repeating segments | no |
| `/write <path> <content>` | `skWrite` | deterministic file output | no |
| `/loop <items>` | `skLoop` | data-driven fan-out: splices a sub-plan per item | no (the loop itself; items come from prior steps) |
| `/report <title>` | `skReport` | checkpoint visible to the user | no |

### Chat-level verbs (wrappers around engine steps + chat state)

| Verb | Description |
|------|-------------|
| `/send <text>` | start a new user turn (idle-only) |
| `/steer <text>` | inject a directive at the next action boundary (does not interrupt the in-flight step) |
| `/queue <text>` [on-action/on-finish] | hold until the chosen gate opens |
| `/flush` | flush the queue immediately |
| `/plan <goal>` | ask the agent to **produce a plan in the DSL** for the given goal |
| `/run <plan-dsl>` | run a plan (or pasted plan text) through the same dispatcher |
| `/save [path]` | persist the session JSONL |
| `/quit` | end the session |

### Workspace / session / story / state (the infra verbs, currently repl-only but folded into chat)

These are the non-model, deterministic commands the planner's plan may also call:

| Verb | Description |
|------|-------------|
| `/ws status \| list \| new <name> \| switch <path>` | workspace management |
| `/session new [path] \| status` | session management |
| `/story chapter validate <file>` | deterministic quality check |
| `/story chapter write <path> -p <premise> [--skip-validate]` | generate a chapter (uses `skGenerate` internally) |
| `/story wiki edit <file> -p <directive>` | update wiki entry (uses `skGenerate` internally) |
| `/state list \| ingest -p <text> <file> \| load <file>` | baked-state cache ops |
| `/cuda status` | GPU probe |
| `/planner --dry <goal>` | deterministic `interpret` without the model (offline plan draft) |

### Mapping to the existing codebase

- **engine steps** come from `src/engine.nim` (the `kind` enum: `skExtract`, `skGenerate`, `skLoop`, `skReport`, `skSummarize`, `skValidate`, `skWrite`) and `src/program.nim` (the DSL serialization — already round-trips to/from JSON via `planToJson`).
- **plan tool** is `pipelineTool` in `src/pipeline.nim` (the JSON-arguments tool the model currently emits as `[tool] run_pipeline {intent, target}`). Under 2111 this becomes the model's natural way to produce a plan that the dispatcher then parses.
- **chat command verbs** (`/send`, `/steer`, `/queue`, `/flush`, `/save`, `/quit`, `/plan`, `/run`) live in the new threaded `chat.nim` dispatcher loop.
- **infrastructure commands** (`/ws`, `/session`, `/story`, `/state`, `/cuda`, `/planner`) are currently in `repl.nim` — they fold into `chat` as `/`-prefixed commands, no reimplementation needed.

### Unified invariant

> **A plan is a script of commands in the same grammar a human types.**
> The dispatcher runs them indistinguishably.
> The agent emits one; the human pastes the same thing back — same code path.

## Follow-ups (this RFC does not implement)

- [ ] Multithreaded `chat` (reader + agent threads; inbox with gates)
- [ ] First-class serializable DSL plan (`interpret` → DSL; back)
- [ ] `/plan` round-trip into `engine.run`
- [ ] Fold `repl`/`chat` binaries into aliases of `chat`
- [ ] Define the exact grammar of one command line (tokenizer reuse from repl)