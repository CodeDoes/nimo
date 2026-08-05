# 9660 — Ritual Interfaces

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Human workflows are rituals—review, brainstorm, revise, publish. Encode them as first-class plan templates with pause points and clear roles.

## Proposed protocol

A ritual is a plan template containing human gates, artifact schemas, timers, and optional generative steps. The engine cannot cross a human gate without an explicit acknowledgement event.

## Invariants

- Human approval is a recorded event, never inferred from elapsed time.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Teams can repeat high-quality editorial processes while preserving their own language and practices.

## Risks and staging

Rituals can become bureaucracy. Templates must remain easy to fork and simplify.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
