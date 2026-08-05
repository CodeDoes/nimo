# 9640 — Attention Weather

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Model context has weather: clear fronts, storms of irrelevant detail, and dangerous pressure from conflicting instructions. Make that visible and manageable.

## Proposed protocol

Before generation, a deterministic analyzer reports context composition, token budget, source age, conflict density, and focus score. The orchestrator can slice or summarize according to declared policy.

## Invariants

- Weather is advisory; it never silently removes source material. Every omission is listed.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Users see why a generation received a focused slice rather than a giant blob.

## Risks and staging

Heuristics are imperfect. Avoid claiming a scientific measure of “attention.”

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
