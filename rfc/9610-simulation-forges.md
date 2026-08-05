# 9610 — Simulation Forges

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Plans should be testable in miniature worlds before they touch reality: mock workspaces, fake tools, and hostile edge cases.

## Proposed protocol

A forge manifest supplies fixture artifacts, deterministic generators, expected invariants, and fault injections. The engine runs a plan against the forge and produces a trace diff.

## Invariants

- Forge execution cannot access real workspace paths, network, or real model state unless explicitly allowed.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

A plan template earns confidence through behavioral scenarios, not just unit tests of helpers.

## Risks and staging

Mocks can lie. Maintain a small suite of explicitly marked real-backend probes.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
