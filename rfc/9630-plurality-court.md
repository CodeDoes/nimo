# 9630 — Plurality Court

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

When plans affect consequential artifacts, a small court of differently configured critics should deliberate in public structured claims before a decision.

## Proposed protocol

Prosecution, defense, and clerk receive the same artifact packet. They emit claims with citations; the clerk applies a deterministic decision policy and produces a verdict or escalates to a human.

## Invariants

- No critic may vote on unstated criteria. The clerk cannot invent evidence.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

High-impact changes gain transparent challenge without delegating authority to a model.

## Risks and staging

A court can theatricalize ordinary work. Use only for configured high-impact categories.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
