# 9530 — Agent Biomes

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Replace a monolithic agent with a temporary biome of tiny specialist organisms—scout, archivist, critic, builder—whose interfaces are artifacts, not chat.

## Proposed protocol

A biome manifest declares roles, budgets, allowed steps, and handoff schemas. The engine schedules only acyclic artifact dependencies; an arbiter resolves conflicts using deterministic rules.

## Invariants

- No role gets unrestricted tools or shared hidden state. Every handoff is persisted and attributable.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

A complex plan yields diverse, traceable proposals without recursive tool chatter.

## Risks and staging

More agents can mean more theater. Start with two-role biomes and compare against one focused plan.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
