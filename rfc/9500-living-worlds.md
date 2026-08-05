# 9500 — Living Worlds

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

A workspace should be able to behave like a place rather than a folder: its people, locations, promises, and unfinished scenes continuously constrain future work.

## Proposed protocol

WorldPulse reads only changed artifacts, produces deterministic fact candidates, then asks a bounded verifier to accept, reject, or flag conflicts. Accepted facts become dated ledger entries; generation receives the smallest relevant slice.

## Invariants

- No fact may silently overwrite another; every assertion has source artifacts, confidence, and a valid-time range. A world may be paused at any time.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Continuity errors per generated chapter fall while prompt size remains bounded.

## Risks and staging

A “living” system can become noisy or invent history. Start with append-only ledgers and explicit human acceptance.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
