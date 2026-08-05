# 9650 — Artifact Economy

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Make every step pay for inputs and outputs with explicit cost: tokens, time, disk, GPU residency, and human attention.

## Proposed protocol

The engine attaches a budget envelope to plans. Steps estimate and account costs; expensive work needs a reservation, and reports show cost versus value signals.

## Invariants

- Budgets stop work safely before a limit; they never hide partial artifacts.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Long-running plans become predictable enough to run on constrained local machines.

## Risks and staging

Bad estimates can be annoying. Begin with reporting before enforcement.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
