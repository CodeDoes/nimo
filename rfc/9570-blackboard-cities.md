# 9570 — Blackboard Cities

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

A plan can be a city: independent services leave structured notices on a public blackboard, while the engine enforces zoning, budgets, and curfews.

## Proposed protocol

Notices are typed proposals, questions, facts, and artifacts. Steps subscribe only to declared notice types; the engine runs a bounded market round and then compiles a normal linear plan.

## Invariants

- The blackboard is not hidden chain-of-thought. Notices must be concise, user-auditable operational data.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Cross-cutting work discovers useful connections without a single giant context prompt.

## Risks and staging

A shared board can devolve into noise. Enforce schemas, size caps, and expiry.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
