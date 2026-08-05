# 9560 — Ontological Git

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Version control should understand “Kael is injured” as a semantic change, not just a line diff.

## Proposed protocol

Extract normalized claims from selected artifacts, then store claim commits alongside file commits. A semantic diff reports added, removed, contradicted, and temporally shifted claims.

## Invariants

- Claims never replace files; they are derived annotations with source spans. Ambiguous extraction is marked ambiguous.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

A review can answer what changed in the world, not only what changed in Markdown.

## Risks and staging

Extraction errors can create false certainty. Confidence and source links are mandatory.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
