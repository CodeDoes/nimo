# NIMO Architecture — Design Principles

This is the *conceptual* spec: what the system is trying to be, and the design
rules that follow from how the RWKV model actually behaves. It's deliberately
plain — no implementation details — because it's the mental model we build the
code against.

## The one-line truth

> NIMO is a loop that talks to a small model, where the *coherence* lives in a
> **program** and **baked states**, not in the model's attention or weights.

## The core loop

```
user message
   │
   ▼
interpreter ──► compile the message into a PROGRAM (a plan = data)
   │
   ▼
executor ──► runs the plan step by step, forever if needed
   │          (each step: extract / summarize / generate / validate / write)
   ▼
reporter ──► streams results to the user as they happen
```

The user message is **compiled into an engine**, not answered. The engine is a
persistent, resumable, observable process that keeps working the goal.

## Design principles

### 1. A planner is a decomposer, not a creator

The planner has exactly one skill: take something too big and break it into
parts small enough to *do*. It produces no prose, no style, no creativity — only
**structure** (a machine-readable plan). Structures can be validated by a
parser; mistakes become parse errors, never weird output.

Creativity lives entirely elsewhere: in the **output-states** (baked states
that produce a certain *sort* of output).

### 2. Intelligence ≈ structure, not context length

This is **not** about fitting more tokens in a context window. RWKV already
handles long contexts. The point is *using the model intelligently*: a small
model acts much bigger than it is when a program holds the structure and the
model only performs each local step well.

```
  "here's the outline, write chapter 3"   ← local, easy for a small model
  "is this ≥500 words, ≥5 paragraphs?"     ← deterministic, no model needed
  "find Kael's facts and remind me"        ← retrieval, not reasoning
```

The executive function — what to do next, in what order, what to check, what to
remember — lives in the machinery. The model is a good, focused executor.

### 3. State-tuning instead of weight-tuning

A 100B model installs skills into its weights via millions of dollars of
fine-tuning. But a "skill" is really just *a reliable way to produce a certain
sort of output* — and RWKV can get that from a **baked state**: cheap, instant,
no gradients.

> Our theory: what big models learn with expensive fine-tuning, a small model
> can approximate with a **real program** (the reasoning) plus **many smaller
> state tunes** (the behaviors).

There are two species of baked state:

| Species | Job | Output |
|---------|-----|--------|
| **Planner state** | turn a fuzzy goal into structured steps | a plan (data) |
| **Output state** | produce a certain *sort* of prose | text (chapter, wiki, outline, critique, summary) |

A baked state only encodes the *sort of output* you want — because you can have
a separate bake that produces **plans** to be executed deterministically.

### 4. Pointed tools beat sub-planners

Most large tasks don't need recursive decomposition. Pointed, single-purpose
tools do the decomposition by slicing *information* instead of splitting the
*goal*:

- `extract` — pull just the slice that's relevant (outline events for one
  character; outline segment for one chapter)
- `summarize` — condense a section into its essence
- `validate` — deterministic quality gate
- `lookupMemory` — pull relevant remembered facts
- `write` — deterministic file output
- `generate` — the only step that needs the model to *think* (via an
  output-state), and only on a focused slice

A sub-planner is a rare escape hatch, used only when a step genuinely isn't
reducible to pointed tools — and even then, you'd usually `summarize` to
condense rather than decompose.

### 5. One kind of thing at a time

Empirical behavior of RWKV (observed):

| Behavior | Consequence |
|----------|-------------|
| reliably resumes a pattern, effectively forever | fixed step templates = guaranteed coherent continuation |
| holds surprisingly a lot in state | allow long continuous output (a chapter, a recap) |
| **mixes or forgets** different *sorts* in one state | never make it hold heterogeneous content at once |

Rule: **the model holds ONE kind of thing at a time.** Different sorts live in
the machinery (outline.md, wiki/, per-chapter files, memory categories). The
executor fetches the relevant slice per step — it never asks the model to
multiplex plot + characters + world + rules + meta in one prompt.

```
BAD : "write chapter 3: here is the whole outline, all characters, the world
       bible, the themes, 3 recaps, and 5 rules."
GOOD: generate(chapterState, context = [outline_slice_for_ch3, wiki_for_ch3])
```

### 6. Streaming is the default — never wait

The moment a token is sampled, it must be visible. There is no "waiting while
the model generates." Every `Generate` step *emits* tokens as they appear.

```
Generate(session, prompt, sink)     # sink called once per token, immediately
```

Generating is watching the model think, in real time. The same streaming
primitive feeds the terminal, the TUI, and the log file.

### 7. The plan is data — make it resumable, interruptible, observable

Because the plan is a data structure (not model prose), the engine around it
gets these properties almost for free:

- **Resumable** — save the plan + cursor (+ state) → continue from step N
- **Interruptible** — stop mid-stream, edit a step or re-plan, resume
- **Observable** — two live layers: token-level (streaming text) and
  step-level (▶/✔ checkpoint events)

## The system anatomy

```
┌──────────────────────────────────────────────────────────┐
│  PLANNER  (learned, structure-only)                      │
│  "fuzzy goal -> flat list of pointed steps"              │
│  ── distilled from frontier traces                       │
└───────────────────────────┬──────────────────────────────┘
                            │ plan (data)
┌───────────────────────────▼──────────────────────────────┐
│  EXECUTOR  (deterministic machinery, written once)       │
│  runs the plan forever; streams; checkpoints; resumes    │
│  data-driven loops fan out over extracted lists          │
└────────────┬───────────────────────────┬─────────────────┘
             │ per step                  │ per step
     ┌───────▼────────┐          ┌────────▼────────┐
     │ POINTED TOOLS  │          │ OUTPUT STATES   │
     │ extract        │          │ outline.state   │
     │ summarize      │          │ chapter.state   │
     │ validate       │          │ critic.state    │
     │ lookupMemory   │          │ summarizer.state│
     │ write          │          │     …           │
     └────────────────┘          └─────────────────┘
             │                              │
             └──────────┬───────────────────┘
                        ▼
              THE MODEL (2.9B, always small,
              always focused, never fine-tuned
              once, always streaming)
```

## The Engine that runs forever

A user message compiles into an **engine**: a persistent loop that

1. walks the plan (extract → summarize → generate → validate → write),
2. splices data-driven loops from extracted lists,
3. streams every token,
4. checkpoints for resume, and
5. can be re-aimed with a new message (re-extract, continue).

It runs indefinitely because each cycle is fresh pointed work on a focused
slice — it never accumulates the heterogeneous clutter that makes the model
drift, mix, or forget.

## See also

- [rfc/3500-plan-format.md](../rfc/3500-plan-format.md) — the plan artifact (step vocabulary, data loops)
- [rfc/3600-engine.md](../rfc/3600-engine.md) — the streaming executor (sink, checkpoint, resume)