# 9520 — Dream Compiler

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Turn ambiguous creative wishes into a constellation of constrained “dreams”: cheap alternate plans that compete before expensive generation begins.

## Proposed protocol

Compile a goal into 3–7 plan candidates with declared assumptions. Deterministic validators score feasibility; the user or a policy selects one, while rejected dreams remain inspectable.

## Invariants

- Dreams may not write workspace artifacts or call generation until promoted. Selection criteria are recorded.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Users can compare radically different structures for the same premise in seconds.

## Risks and staging

Candidate explosion can become performative. Cap count, cost, and nesting depth.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
