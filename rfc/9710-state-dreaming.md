# 9710 — State Dreaming: Evidence-Gated Continual Improvement for RWKV

**Status: speculative research RFC.** This RFC proposes an offline “dream”
cycle for NIMO. It does **not** authorize autonomous changes to model weights,
state bakes, workspace artifacts, or user-visible behavior. The first deliverable
is an offline, inspectable trace-and-evaluation pipeline.

## Abstract

OpenClaw’s built-in dreaming frames dreaming as an optional, scheduled memory
consolidation pass: it scores short-term signals, promotes qualified items to
long-term memory, and writes a human-reviewable dream diary. That is an
excellent discipline for *facts*. It is insufficient for improving an agent’s
*behavior*: a memory entry saying “the extract step failed” does not itself make
the next extract more reliable.

NIMO can explore a different division of labor enabled by a state-space model:

- **memory** keeps durable, inspectable facts and source artifacts;
- **plans and validators** keep execution deterministic;
- **state bakes** encode a narrow, reusable *mode of behavior*—for example,
  “emit a flat, valid plan” or “write a chapter from one focused beat”; and
- a sleeping curator turns outcome-labelled past traces into proposed,
  evaluated, versioned bake examples.

The key claim is deliberately modest: instead of continuously fine-tuning
weights, NIMO can continually improve its *library of baked contexts* and the
policy that selects them. A bake is accepted only when held-out, reproducible
checks show a benefit and regression guards are satisfied.

## Research context

OpenClaw’s documented dreaming uses thresholded promotion, recall frequency,
query diversity, scheduled sweeps, and a reviewable `DREAMS.md` diary
([OpenClaw memory documentation](https://github.com/openclaw/openclaw/blob/main/docs/concepts/memory.md)).
The practical concern is real: an OpenClaw issue reports that running dreaming
for all workspaces in one scheduled sweep can create memory pressure, arguing
for per-agent scheduling and control
([issue #67413](https://github.com/openclaw/openclaw/issues/67413)).

Recent agent-memory research similarly treats offline consolidation as an
optimization problem rather than indiscriminate summarization. Auto-Dreamer
uses offline consolidation over agent trajectories and evaluates replacement
memory against downstream task reward
([Auto-Dreamer](https://arxiv.org/html/2605.20616)). A separate “Sleep”
proposal combines memory consolidation with synthetic rehearsal, while warning
that repeated self-improvement risks catastrophic forgetting
([Language Models Need Sleep](https://arxiv.org/html/2606.03979v1)).

RWKV makes a state-oriented experiment unusually attractive. State tuning
research investigates adapting RWKV-7’s state while leaving pretrained weights
fixed ([State Tuning](https://arxiv.org/html/2504.05097v1)); state-centric
retrieval work reports that reusable RWKV states can decouple later processing
from document length ([EmbeddingRWKV](https://arxiv.org/html/2601.07861v1)).
Those papers are motivation, not proof that NIMO’s proposed bake selection will
work. NIMO must measure its own model, tasks, and hardware.

## Terminology

| Term | Meaning |
|------|---------|
| **wake trace** | The auditable record of one completed or aborted plan run. |
| **episode** | A compact, source-linked view of a wake trace suitable for offline analysis. |
| **bake example** | A templated demonstration/context that is evaluated through RWKV to create a starting state. It is not a weight update. |
| **skill bundle** | A versioned manifest containing a template, curated examples, bake state, compatibility data, and evaluation evidence. |
| **dream** | An offline proposal to create, revise, retire, or route a skill bundle. A dream is not automatically deployed. |
| **canary** | A held-out, fixed evaluation task used to compare a candidate bundle with its parent/baseline. |

## Design principle: improve behavior, not mythology

A dream diary is useful for humans, but a poetic reflection must never be
mistaken for evidence that the agent improved. NIMO therefore separates four
artifacts:

1. **Raw evidence** — immutable plan, tool, validator, and output records.
2. **Candidate hypothesis** — a concise claim such as “a two-example planner
   bake reduces malformed `[step]` emissions for story goals.”
3. **Reproducible evaluation** — fixed seeds where supported, model/version
   identifiers, canary inputs, metrics, and raw outputs.
4. **Promotion decision** — deterministic policy result plus a human approval
   event for any activation.

The model may help discover hypotheses and draft examples. It cannot mark its
own hypothesis as true, approve a bundle, or alter raw evidence.

## Architecture

```text
                         WAKE: normal user work
user -> Plan -> Engine -> steps/tools -> artifacts + validation + outcome
                         |                           |
                         +----- append-only trace ----+
                                                     |
                                                     v
                    SLEEP: bounded offline curator
           select episodes -> discover patterns -> propose examples
                    |                 |                   |
                    |                 v                   v
                    |          counterexamples       candidate bundle
                    |                                     |
                    +---------- fixed canary evaluation <-+
                                                          |
                             promote / reject / quarantine / request review
                                                          |
                                                          v
                  versioned skill registry -> explicit runtime routing only
```

### 1. Wake trace capture

Every executed plan should eventually emit a compact `DreamTrace` in the
session history or a sidecar JSONL file. It references, rather than duplicates,
large artifacts:

```nim
type DreamTrace = object
  traceId: string
  sessionId: string
  planId: string
  goalClass: string              # e.g. planner, chapter, extract
  modelSig: string
  bakeRef: string                # exact active bundle, or "none"
  stepSummaries: seq[StepSummary]
  artifactRefs: seq[string]      # immutable paths/hashes
  outcome: OutcomeSignals
  consentScope: string

type OutcomeSignals = object
  deterministicPasses: seq[string]
  deterministicFailures: seq[string]
  elapsedMs: int64
  tokens: int
  userAccepted: bool             # explicit only; absence is unknown
  userCorrectionRef: string
  abandoned: bool
```

A success signal must not be inferred from silence. Deterministic checks,
explicit approval, explicit correction, and abandonment are separate signals.
Sensitive source text must be redacted or excluded before a trace enters a
sleep corpus.

### 2. Episode selection and discovery

The curator performs a budgeted, per-workspace sweep. It should prefer:

- repeated **successes** with a clear, narrow behavior and good validation;
- **paired contrasts**: similar goals where one trace passed and another
  failed, especially when a validator explains the difference;
- repeated user corrections that point to the same missing constraint;
- high-cost failures, where a small state improvement could save many tokens;
- diverse examples that cover different inputs without mixing output kinds.

It should reject or quarantine traces with absent outcomes, policy violations,
unresolved conflicts, secret-tainted sources, or synthetic-on-synthetic
lineage beyond a configured depth.

The discovery model may cluster episodes and propose a hypothesis, but the
candidate generator must produce both **positive examples** and
**counterexamples**. This is the defense against teaching a skill to imitate a
single accidental success.

### 3. Candidate bake construction

A candidate is a small, self-describing bundle—not an opaque `.state.bin`:

```json
{
  "id": "planner.story.v3",
  "parent": "planner.story.v2",
  "kind": "planner",
  "modelSignature": "sha1:…",
  "template": "Goal: {{goal}}\nEmit [step] lines only:\n",
  "examples": [
    {"traceRef": "…", "role": "positive", "text": "…", "redacted": true},
    {"traceRef": "…", "role": "counterexample", "text": "…"}
  ],
  "bakeRecipe": {"order": ["template", "examples"], "maxTokens": 900},
  "stateRef": "states/planner.story.v3.state.bin",
  "evidenceRef": "evals/planner.story.v3.json",
  "status": "candidate"
}
```

For the initial implementation, “creating a bake” means concatenate the
curated template and examples according to the recipe, evaluate that context
once through the RWKV model, and persist the resulting state with model/vocab
signatures. This is **state baking**, not gradient-based state tuning and not
weight training.

A later research lane may test optimized state tuning, but it must use a
separate format, separate evaluator, and an explicit opt-in. A state obtained
from a demonstration is reproducible and easy to roll back; silently optimized
state is not an acceptable starting point for continual improvement.

### 4. Evaluation before promotion

Candidates compete against their parent or an unbaked baseline on three fixed
sets:

| Set | Purpose | May influence promotion? |
|-----|---------|--------------------------|
| development | iteration while constructing a candidate | No |
| canary | held-out behavior and regression checks | Yes |
| sentinel | unrelated capabilities / safety and formatting checks | Yes, only as a veto |

Metrics are typed by skill:

- planner: parse rate, allowed-step rate, plan validator pass rate;
- extractor: citation/source-span precision and deterministic schema pass rate;
- chapter output: deterministic quality gates, repetition rate, explicit human
  acceptance when available;
- operational: tokens, wall time, abort rate, and tool-error rate.

Promotion policy must be deterministic and conservative:

```text
promote only if:
  candidate improves the primary canary metric by configured margin
  AND confidence interval / repeated-trial threshold is satisfied
  AND no sentinel regression exceeds its tolerance
  AND raw evidence + examples are readable
  AND an authorized human approves activation
otherwise: reject, quarantine, or keep as research-only.
```

The system must report *negative* results. A candidate that loses is useful
information and prevents repeated rediscovery of the same bad idea.

### 5. Runtime routing and rollback

The engine never silently chooses the newest bundle. Routing is an explicit,
versioned policy from `goalClass` and workspace configuration to a bundle id.
Each generated artifact records its `bakeRef`, model signature, and trace id.

Activation is an atomic pointer change. Rollback is an atomic pointer reversal;
old states and evidence remain immutable. If the model or vocabulary signature
does not match the bundle, routing refuses it rather than loading an invalid
state.

## Dream-cycle scheduling and resource safety

Borrow OpenClaw’s useful scheduling idea but not a global all-workspace sweep:
NIMO schedules independently per workspace, staggers jobs, and enforces a
resource envelope.

```toml
[dreaming]
enabled = false
schedule = "0 3 * * *"
maxWallSeconds = 900
maxModelTokens = 30000
maxCandidates = 5
maxEpisodes = 100
requireHumanApproval = true
allowNetwork = false
```

- Default is disabled.
- The cycle acquires a workspace lock and writes only to
  `.nimo/dreams/` and `.nimo/skills/candidates/`.
- It never runs concurrently with an active write plan for that workspace.
- It must stop cleanly at its budget and preserve a resumable cursor.
- It has no network access by default and no ability to execute shell tools.

## Curation policy

Curation is where this RFC differs most from “summarize everything nightly.”
A bake example is a training-like asset; it demands stronger provenance.

### Admission rules

1. Every example links to an immutable source trace and artifact hashes.
2. An example has a declared behavior, input class, output schema, and outcome.
3. At least one counterexample or failure boundary accompanies each positive
   pattern when such a boundary exists.
4. A bundle contains one output kind only: planner, extractor, critique, or
   chapter—not a mixed “be good at everything” state.
5. User-authored content is excluded unless its workspace consent policy allows
   local curation; secrets and credentials are never bake material.
6. Synthetic examples are labeled and capped; they cannot become the only
   evidence for a promoted bundle.

### Diversity selection

Ranked episodes should not simply select the top N near-duplicates. Select via
maximal marginal relevance over goal shape, artifact type, validator outcome,
and time. The aim is a compact basis of reliable demonstrations, not a long
prompt disguised as a state bake.

### Human review surface

The curator writes a readable report:

```text
Dream 2026-08-05 / planner.story.v3
Hypothesis: story goals fail less often when the planner sees explicit loop syntax.
Evidence: 8 passed, 5 failed, 3 held-out canaries.
Candidate: 3 positive examples + 2 counterexamples (all source-linked).
Canary: parse rate +12 pp; sentinel: no observed regression.
Decision: CANDIDATE — awaiting approval.
```

A reviewer can inspect, edit, reject, or promote the example set before any
state is baked or activated.

## Failure modes

| Failure | Guard |
|---------|-------|
| self-reinforcing hallucination | require raw sources, counterexamples, held-out canaries, and human approval |
| catastrophic skill regression | sentinel suite, parent baseline, immutable rollback |
| overfitting to one user/workspace | workspace-local bundles by default; cross-workspace export requires explicit review |
| privacy leakage | local-only default, redaction before corpus admission, no network by default |
| resource spikes | per-workspace schedules, locks, token/wall-time budgets, resumable cursors |
| confusing state bake with learned weights | separate terminology, manifest fields, and provenance for baked versus optimized state |
| opaque autonomous changes | append-only dream reports and explicit activation events |

## Phased research plan

### Phase A — no model, no writes outside `.nimo/dreams/`

Implement `DreamTrace`, consent/redaction checks, deterministic outcome scoring,
episode ranking, bundle manifests, and a review report. Unit-test admission,
exclusion, diversity, budget stops, and deterministic promotion policy.

### Phase B — offline canary harness

Add fixture traces and a mock generator. Test that a candidate is rejected for
a sentinel regression, insufficient evidence, duplicate examples, missing source
links, or an incompatible model signature.

### Phase C — manual local bake experiments

A developer explicitly selects an approved candidate. NIMO bakes it using the
existing context-to-state mechanism, runs fixed canaries on the real local model,
and saves raw outputs. Nothing is auto-activated.

### Phase D — guarded activation

Enable workspace-local routing behind an explicit configuration flag. Promotion
still requires approval. Add rollback, cohort comparison, and scheduled but
resource-capped curation.

### Phase E — research-only optimized states

Only after Phases A–D show repeatable gains should NIMO investigate state-tuning
or learned state editors. This requires a new RFC and direct comparison against
simple demonstration baking; complexity is not evidence of value.

## Falsifiable hypotheses

1. For narrow planner tasks, curated demonstration bakes improve held-out plan
   parse rate versus an unbaked prompt without increasing sentinel failures.
2. Selecting diverse, outcome-labelled examples outperforms selecting the most
   recent or most frequently recalled examples.
3. Pairing successes with validator-explained failures reduces repeated failure
   modes more than positive-only curation.
4. A per-workspace, budgeted curator produces useful candidates without
   materially affecting interactive latency or active workspace integrity.

Failure to confirm any hypothesis is a valid result and should simplify or end
the corresponding mechanism.

## See also

- [8000-state-bake.md](8000-state-bake.md) — existing context bake mechanism
- [1000-session.md](1000-session.md) — provenance and history
- [3500-plan-format.md](3500-plan-format.md) — plan data and checkpoints
- [3600-engine.md](3600-engine.md) — deterministic streaming execution
- [9300-eval.md](9300-eval.md) — offline behavioral testing
- [9620-skill-genomes.md](9620-skill-genomes.md) — speculative skill provenance
- [9550-memory-ecology.md](9550-memory-ecology.md) — speculative memory curation
