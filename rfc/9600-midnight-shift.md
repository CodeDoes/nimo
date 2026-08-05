# 9600 — Midnight Shift

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

NIMO could run a safe overnight maintenance shift: organize notes, detect stale plans, propose wiki gaps, and leave a morning briefing—without creating surprise content.

## Proposed protocol

A scheduled run operates only on read-only scans and proposal artifacts. It emits a review queue and never calls write/merge outside an inbox directory.

## Invariants

- No model-generated change reaches canonical workspace files unattended. Budgets and quiet hours are mandatory.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

A morning briefing identifies high-value maintenance work from an otherwise dormant workspace.

## Risks and staging

Automation can feel invasive. Make it opt-in, local-first, and visibly logged.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
