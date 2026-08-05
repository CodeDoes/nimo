# 9680 — Mythic Observability

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Observability need not be sterile: a long-running plan can narrate its own operational myth—maps, quests, and constellations—while retaining exact technical trace data.

## Proposed protocol

A renderer maps canonical events to poetic metaphors using a deterministic theme pack. Users can toggle between mythic and literal traces at any instant.

## Invariants

- Metaphor is presentation only; exact step ids, timings, and errors remain one action away.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Long runs feel legible and engaging without sacrificing debuggability.

## Risks and staging

Playfulness must not obscure failure. Errors always render literally first.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
