# 9620 — Skill Genomes

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Treat baked skills as evolving, inspectable genomes with templates, examples, state references, traits, and compatibility metadata.

## Proposed protocol

A skill bundle records parent bundles, benchmark results, target output shape, and allowed step kinds. Mutation creates a new bundle; promotion requires model-eval evidence.

## Invariants

- A state blob is never anonymous. Every use records exact bundle id and model compatibility.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

Skill experiments become reproducible and comparable rather than mysterious files.

## Risks and staging

Metaphors can obscure simple files. The wire format remains boring JSON plus state bytes.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
