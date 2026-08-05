# 9550 — Memory Ecology

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Memory should be an ecosystem with decay, migration, lineage, and competing interpretations—not an immortal pile of snippets.

## Proposed protocol

Each memory has salience, provenance, category, dependencies, and review time. A periodic deterministic gardener proposes compact summaries, archival moves, or conflict clusters; nothing is deleted without policy approval.

## Invariants

- Raw sources remain recoverable. Summaries link to their descendants and parents.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Retrieval stays useful as a workspace grows for months rather than merely days.

## Risks and staging

Automated pruning can erase nuance. Use append-only tombstones and reversible policies.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
