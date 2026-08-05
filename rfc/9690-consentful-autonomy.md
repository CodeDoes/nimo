# 9690 — Consentful Autonomy

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Autonomy should be negotiated like a contract: the user grants narrow, revocable powers with duration, scope, and audit requirements.

## Proposed protocol

Capability grants are signed local policy records. Each engine step checks grants before execution and emits a denial or use receipt; expiry pauses plans cleanly.

## Invariants

- Default authority is read-only and ephemeral. Revocation is immediate and does not erase audit history.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Users can safely delegate bounded maintenance and generation without surrendering control.

## Risks and staging

Policy UX can become onerous. Offer sensible presets that remain inspectable.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
