# 9540 — Narrative Physics

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Stories can have conservation laws: wounds heal at a cost, journeys take time, secrets have witnesses, and consequences propagate like physics.

## Proposed protocol

A world declares predicates and transition rules. Extract steps propose state transitions; a deterministic simulator accepts only legal transitions and emits contradictions as repair tasks.

## Invariants

- Rules are versioned and local to a workspace. The simulator never authors prose.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Detected continuity violations become actionable before a chapter is saved.

## Risks and staging

Overformalizing fiction can flatten it. Rules must be opt-in and allow explicit miracles.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
