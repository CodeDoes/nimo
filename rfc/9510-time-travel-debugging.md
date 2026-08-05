# 9510 — Time-Travel Debugging for Plans

**Status: speculative research RFC.** This is deliberately wild. It defines a
possible direction, not a shipped feature, and it must not be represented as
implemented until an RFC-first implementation plan and offline tests exist.

## Premise

Every engine run should be replayable as a causal film: inspect any step, change one input, and fork the future without rewriting the past.

## Proposed protocol

Checkpoint plans, focused inputs, tool outputs, model signature, skill reference, and sink transcript. A rewind opens a branch at a checkpoint; replay either reuses recorded nondeterministic outputs or deliberately regenerates them.

## Invariants

- A replay never mutates the original branch. Reused outputs and regenerated outputs must be visibly distinct.
- The existing core remains small: `Session`, `Plan`, `Step`, `Engine.run`,
  `bootstrapSession`, and pointed tools.
- Model output stays non-authoritative; deterministic code and explicit user
  decisions own persistence, permissions, and state transitions.

## Evidence of success

A failed long run can be diagnosed and repaired from one checkpoint without rerunning completed work.

## Risks and staging

Full token/state capture is expensive. Begin with artifact and step-level replay, then make token capture opt-in.

A prototype must begin offline, use fixture artifacts, and add a behavioral
unit test before it touches the real model or a user workspace.

## Related work

- [3500-plan-format.md](3500-plan-format.md) — plan-as-data
- [3600-engine.md](3600-engine.md) — streaming, checkpointed execution
- [1000-session.md](1000-session.md) — auditable history and provenance
