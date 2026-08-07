# RFC 2111 — Unified Chat & the Command DSL

**Status:** design (supersedes the repl-only framing of RFC 2110)
**Category:** 2 — CLI / User Interface
**Author:** user + Agnes (design review)

## One turn starts, step by step: vocabulary

Two sizes of grain matter, and mixing them is the root of most confusion:

- **`turn`** — a complete, addressable exchange. A **user turn** (the input)
  or an **assistant turn** (the agent's full reply: plan → steps → final
  answer). A session is a sequence of turns.
- **`step`** (synonym: **`action`**) — an *atomic* action *inside* a turn:
  one `Generate`, one `tool_call`, a `validate`, a `write`, a step in a plan.
  Steps are the grain at which steering and interruption inject, never turns.

The practical rule: **a `turn` is conversational; a `step` is mechanical.**
The agent loops over steps; the conversation counts turns.

## The claim

The user-facing grammar and the plan grammar are **the same DSL**.

- `/`-prefixed lines a human types are **commands**.
- A **plan** is literally a sequence of those same commands (a scripted DSL).
- Therefore the **command dispatcher is the plan executor** — one interpreter.
  A plan the drone emits and a sequence a human types both run through the
  exact same code path.

> Consequence of the "coherence in the program" principle: a plan is **data
> you can read, edit, copy, and paste back** — and pasting a plan is just
> re-running commands through the same dispatcher. There is no second,
> private, machine-only plan format.

## `chat` is the single interactive entry

One command, one process, **two threads**:

- **Reader thread** owns stdin. Every line goes into a shared inbox. Typing is
  never blocked — the agent is busy, you can still type.
- **Agent thread** runs the turn loop over `engine.run` (the existing plan
  executor) and drains the inbox at safe points.

### State machine

```
idle ──send──▶ busy ──(turn completes)──▶ idle
  ▲              │
  └──queue───────┘   (deliver when idle → send-on-finish)
```

`busy` holds while an assistant turn is executing (any plan/tool/generation).
The loop drains the inbox **between steps**, never mid-step.

## Verbs: send / steer / queue / plan

- **send** — start a new **user turn**.

  Only meaningful when **idle**. (Bare input when idle defaults to this.)

- **steer** — inject a directive **between actions**.
  It does **not** interrupt the currently-forming step. The in-flight action
  (usually a `tool_call`) completes; the steer is applied at the next step
  boundary as clarification/redirection before the next action. Default for a
  bare line when the agent is **busy**.

- **queue** — hold text with a **delivery trigger** (a gate), then send when
  the gate opens:
  - **send-on-finish** — deliver when the session goes `idle`.
  - **send-on-action-completed** — deliver at the next step boundary
    (equivalent to a queued `steer`, just written ahead of time).

  The inbox is therefore not a single pile: each queued message carries its
  gate. `steer` is a message with gate = next-boundary; `queue` = a message
  with a gate you pick.

## Input dialect

- **Bare line** → agent mode.
  - idle → `send`
  - busy → `steer` (default; configurable)
- **`/`-prefixed line** → explicit verb ("repl mode"). Some verbs: `/send`,
  `/steer`, `/queue <gate>`, `/plan`, `/save`, `/story`, `/state`, `/ws`,
  `/help`, `/quit` …

### `plan` (not `planner`)

- `/plan <goal>` — the **agent** thinks and produces a plan **in the DSL**.
  Output is a copyable, editable plan artifact.
- Feed that plan back in (paste / `/run`) and it executes through the same
  dispatcher — the same path the drone's own turn uses. Deterministic,
  inspectable, resumable.

## Migration

- New `src/chat.nim` becomes the interactive entry.
- Old `repl.nim` and `chatCL` remain as **aliases** that open `chat` (zero-loss
  migration); drop them once the alias proves stable.
- RFC 2110's "one registry, two drivers" collapses: the registry is the DSL,
  and the drone vs. human distinction is only *who* types the commands.

## Rejected & clarified (from earlier confusion)

- `send` and `steer` are **not** aliases. They differ by *when* they act
  relative to the turn/tool boundary.
- `steer` is not a mid-token interrupt; it is a boundary injection.
- A bare message is still never implicitly a `tool` — but with threading, the
  receiver can *react* to input while busy (that's what a busy-`steer` is).
- Plans are not a separate binary format; `plan dsl ≡ command dsl`.

## Builds on

- [3500-plan-format.md](3500-plan-format.md) — the plan as a data workhorse
- [3600-engine.md](3600-engine.md) — the streaming executor (`engine.run`)
- [2110-repl.md](2110-repl.md) — the protocol it supersedes

## The DSL: Nim-script plan templates

Plans are **Nim script templates** — valid Nim code that compiles to plan
steps and runs through the engine. This gives you:

- Full Nim syntax (variables, loops, conditionals, string interpolation)
- Natural-language prompts inside `structured()` calls
- Schemas as Nim `object` types
- One primitive: `structured <SchemaType> "<prompt>"`

### Core syntax

```
nim
# Variable binding
let outline = structured StoryOutline "create a story for: " & premise

# String interpolation
let context = "extract characters from: " & outline

# Control flow
for char in characters:
    let wiki = structured CharacterWiki "wiki for: " & char.name
    save "wikis/" & char.name & ".json", wiki

# Conditional
if validate(chapter):
    save "chapter.md", chapter.content
else:
    chapter = structured Chapter "revise: " & chapter.content
    save "chapter.md", chapter.content

# Checkpoint
say "done"
```

### Schema definition

```
nim
type
  StoryOutline* = object
    premise*: string
    acts*: seq[string]
    characters*: seq[string]
  
  CharacterWiki* = object
    name*: string
    traits*: seq[string]
    backstory*: string
  
  Chapter* = object
    title*: string
    content*: string
    wordCount*: int
```

Schemas are Nim `type` definitions. The `structured()` call generates output
that conforms to the schema. The engine validates and binds to the variable.

### The `structured()` primitive

```
nim
let <variable> = structured <SchemaType> "<natural language prompt>"
```

Expands to:
1. `Generate(prompt)` — model produces text
2. `Parse<SchemaType>(output)` — deserialize into the schema
3. `Bind(variable, parsed)` — store in variable scope

That's it. Everything else is Nim syntax around this primitive.

### Full example: story pipeline

```
nim
# Inputs
let premise = "a lighthouse keeper discovers a message in a bottle"

# Step 1: generate outline
let outline = structured StoryOutline "create a story outline for: " & premise
save "outline.json", outline

# Step 2: extract characters
let characters = structured seq[CharacterWiki] "list main characters from: " & outline

# Step 3: generate wikis
for char in characters:
    let wiki = structured CharacterWiki "write wiki entry for: " & char.name
    save "wikis/" & char.name & ".json", wiki

# Step 4: generate chapters
for i in 1..3:
    let chapter = structured Chapter "write chapter " & $i & " about: " & outline
    if validate(chapter):
        save "chapters/ch" & $i & ".md", chapter.content
    else:
        let revised = structured Chapter "revise chapter " & $i & " (needs more words): " & chapter.content
        save "chapters/ch" & $i & ".md", revised.content

say "story complete"
```

### How it compiles to plan steps

The Nim script compiles to `seq[Step]`:

```
nim
let outline = structured StoryOutline "..."
```

→

```
nim
Step(kind: skGenerate, name: "outline", context: "...", skill: "StoryOutline")
Step(kind: skWrite, name: "save-outline", path: "outline.json", content: <variable:outline>)
```

The compiler translates Nim syntax to the existing engine step types. The
runtime is identical — only the surface syntax changes.

### Variable scope and piping

Variables live in a scope map:

```
nim
let outline = structured StoryOutline "..."
let chars = structured seq[Character] "extract from: " & outline  # uses $outline
```

Piping is just variable reference:

```
nim
# Explicit
let wiki = structured CharacterWiki "..." & char.name
save "path", wiki

# Implicit (last output)
structured CharacterWiki "..." & char.name
save "path"  # saves lastOutput
```

### Natural language prompts

The prompt is **natural language**, not JSON:

```
nim
# Good (natural)
outline = structured StoryOutline "create a story outline for: a lighthouse"

# Bad (mechanical)
Step(kind: skGenerate, name: "generate-outline", context: "Create a story outline...", skill: "output:outline")
```

The model sees the same prompt either way — the Nim script just makes it
readable for humans and editable as a plan artifact.

### Chat-level verbs (Nim-script form)

| Verb | Nim form |
|------|----------|
| send | `send "<text>"` |
| steer | `steer "<text>"` |
| queue | `queue "<text>"` |
| plan | `plan "<goal>"` → returns script text |
| run | `run "<script>"` |
| save | `save "<path>"` (session) |
| quit | `quit()` |

### Infrastructure verbs (Nim-script form)

| Verb | Nim form |
|------|----------|
| workspace | `ws.status()`, `ws.new("name")`, `ws.switch("path")` |
| session | `session.new()`, `session.status()` |
| story | `story.chapter.validate("file")`, `story.chapter.write("path", premise)` |
| state | `state.list()`, `state.ingest("text", "file")`, `state.load("file")` |
| cuda | `cuda.status()` |
| planner | `planner.dry("goal")` |

### Unified invariant

> **A plan is a Nim script of `structured()` calls and variable wiring.**
> The dispatcher runs it. The agent emits it. The human types it.
> One grammar, one executor, three drivers.

## Follow-ups (this RFC does not implement)

- [ ] Multithreaded `chat` (reader + agent threads; inbox with gates)
- [ ] First-class serializable DSL plan (`interpret` → DSL; back)
- [ ] `/plan` round-trip into `engine.run`
- [ ] Fold `repl`/`chat` binaries into aliases of `chat`
- [ ] Define the exact grammar of one command line (tokenizer reuse from repl)