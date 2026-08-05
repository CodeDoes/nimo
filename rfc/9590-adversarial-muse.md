# 9590 — Adversarial Muse

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Give every ambitious output a mischievous, bounded opponent whose only job is to find clichés, contradictions, and boring choices.

## Proposed protocol

After a Generate step, an adversarial critique plan receives the output plus explicit rubric. It produces structured objections; deterministic gates decide whether revision is required.

## Invariants

- The muse cannot write final artifacts, alter plans, or critique without a rubric.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Revision quality improves without turning critique into an endless loop.

## Risks and staging

Relentless criticism can destroy momentum. Limit rounds and let users mute a rubric.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
