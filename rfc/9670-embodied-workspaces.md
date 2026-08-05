# 9670 — Embodied Workspaces

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

A workspace can project itself into multiple bodies: terminal, TUI, printout, audio briefing, and eventually physical displays—one plan, many views.

## Proposed protocol

All views consume the same step and token event stream. Renderers are pure adapters; interaction events become explicit engine commands.

## Invariants

- No renderer owns state or changes plan semantics. Accessibility is a baseline requirement.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

A user can leave a terminal run and resume understanding it from another representation.

## Risks and staging

UI scope can explode. Ship terminal/TUI parity before novel surfaces.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
