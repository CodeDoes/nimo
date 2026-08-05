# 9580 — Counterfactual Labs

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Before changing a story or plan, simulate “what if?” branches and measure their downstream consequences.

## Proposed protocol

Fork an artifact graph, apply one proposed change, run deterministic dependency and continuity checks, then present a delta report. Generative speculation is clearly labeled and never merged automatically.

## Invariants

- Counterfactual artifacts live in isolated branches and cannot alter canonical memory.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Editors can compare consequences of changing a character, constraint, or requirement.

## Risks and staging

Simulations create false authority when inputs are incomplete. Reports must surface unknowns.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
