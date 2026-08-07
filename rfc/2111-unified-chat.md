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

## Follow-ups (this RFC does not implement)

- [ ] Multithreaded `chat` (reader + agent threads; inbox with gates)
- [ ] First-class serializable DSL plan (`interpret` → DSL; back)
- [ ] `/plan` round-trip into `engine.run`
- [ ] Fold `repl`/`chat` binaries into aliases of `chat`
- [ ] Define the exact grammar of one command line (tokenizer reuse from repl)