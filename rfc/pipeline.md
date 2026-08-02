## What is this file for?

RFC for the pipeline DSL — a structured, DAG-based narrative generation system.

## Concept

A NimScript DSL for defining multi-step LLM generation pipelines. Since it's valid Nim code, it gets:
- **Static checking** at script-write time (type errors caught before execution)
- **Native parallelism** via Nim's `parallel` or fork-based execution
- **Composable** — pipeline scripts can import and reuse other pipeline modules
- **Debuggable** — run with `nim script --debug` or step through in a debugger

The DSL is just Nim procs with a DAG scheduler that runs between calls.

## DSL Syntax

```nim
# pipeline.nim — valid NimScript, run with: nim script pipeline.nim

import std/[os, strutils, tables]

# --- Pipeline API (provided by nimo runtime) ---

type
  WikiRef = ref object of PipelineNode
  ChapterRef = ref object of PipelineNode
  ContextRef = ref object of PipelineNode

proc generate(prompt: string, target: string = ""): WikiRef | ChapterRef | ContextRef =
  ## Calls the LLM with prompt, writes to target if provided.
  ## Returns a node ref that downstream steps can reference.
  ...

proc extract(src: PipelineNode, filter: string): ContextRef =
  ## Filters src output to only the relevant excerpt.
  ...

proc summarize(src: PipelineNode, length: string = "brief"): ContextRef =
  ## Condenses src output for downstream consumption.
  ...

# --- User pipeline definition ---

# Step 1: Parallel atomic generation (scheduler runs these concurrently)
let max_wiki = generate(
  "Generate character entry for Max: robot ninja, stealth specialist.",
  target = "wiki/max.md"
)

let rob_wiki = generate(
  "Generate character entry for Rob: heavy ordnance tactical partner.",
  target = "wiki/rob.md"
)

let boss_wiki = generate(
  "Generate character entry for Ghastone: cybernetic syndicate crime boss.",
  target = "wiki/boss.md"
)

let city_wiki = generate(
  "Generate world entry for Neo-Kuroba: high-tech neon cyberpunk city.",
  target = "wiki/city.md"
)

# Step 2: Context extraction (in-memory filtering)
let max_ctx = extract(max_wiki, "Max's combat abilities, gear, and personality traits")
let rob_ctx = extract(rob_wiki, "Rob's equipment, tactics, and background")

# Step 3: Dependent generation (waits for max_ctx + city_wiki)
let ch1 = generate(
  """
  World Setting:
  $#{city_wiki}

  Protagonist Profile:
  $#{max_ctx}

  Task: Write Chapter 1 introducing Max operating solo in Neo-Kuroba.
  """,
  target = "chapters/01.md"
)

# Step 4: Transformation
let ch1_recap = summarize(ch1, length = "bullet_points")

# Step 5: Branching (parallel once ch1_recap is ready)
let ch2 = generate(
  """
  Previous Narrative State:
  $#{ch1_recap}

  Partner Profile:
  $#{rob_ctx}

  Task: Write Chapter 2 introducing Rob as Max's new partner.
  """,
  target = "chapters/02.md"
)

let draft_outline = generate(
  """
  Current Progress:
  $#{ch1_recap}

  Main Antagonist Profile:
  $#{boss_wiki}

  Task: Draft escalation plot beats leading to confrontation with Ghastone.
  """,
  target = "draft_outline.md"
)

# Step 6: Convergence
let ch2_recap = summarize(ch2, length = "bullet_points")

let ch3 = generate(
  """
  Previous Events:
  $#{ch2_recap}

  Task: Write Chapter 3 as Max and Rob uncover Ghastone's illegal operations.
  """,
  target = "chapters/03.md"
)

let ch3_recap = summarize(ch3, length = "bullet_points")

let final_outline = generate(
  """
  Narrative Endpoint (End of Chapter 3):
  $#{ch3_recap}

  Draft Outline:
  $#{draft_outline}

  Task: Finalize the chapter outline for Chapters 4 through 10,
        ending in Ghastone's defeat.
  """,
  target = "outline.md"
)
```

## Execution Model

The NimScript runtime intercepts proc calls and builds a DAG:

```
Phase 1 (Parallel):  generate ×4 (wiki nodes)
Phase 2 (Sequential): extract ×2 (context buffers)
Phase 3 (DAG join):  generate ch1 (waits for max_ctx + city_wiki)
Phase 4 (Parallel):  summarize ch1 → generate ch2, draft_outline
Phase 5 (Sequential): ch2 → ch3 → final_outline
```

Key properties:
- **Topological sort** determines execution order automatically
- **Independent nodes** run concurrently via Nim's `parallel` or forks
- **Context references** (`$#{var}`) are resolved from prior node outputs
- **Targets** are written to disk; intermediate values stay in-memory
- **Variable binding** is static — the Nim compiler catches missing refs

## Node Types

| Node | Purpose | I/O |
|------|---------|-----|
| `generate(prompt, target)` | Call LLM, write to file | prompt → file |
| `extract(src, filter)` | Filter source output to focused context | source → string |
| `summarize(src, length)` | Condense for downstream consumption | source → short string |

## Why This Matters

The current CLI (`nimo chat`) handles linear, interactive chat. This DSL enables:
- **Multi-step creative workflows** (wiki → chapters → outline)
- **Context precision** (only feed relevant excerpts, not full documents)
- **Parallelism** (independent wiki entries generated concurrently)
- **Reproducibility** (same pipeline = same structure, different outputs)

## Why NimScript

| Approach | Pros | Cons |
|----------|------|------|
| JSON/YAML pipeline spec | Simple, language-agnostic | No type checking, no composition |
| Python pipeline | Rich ecosystem | Extra runtime dependency |
| **NimScript DSL** | Type-checked, composable, native parallelism, single binary | Learns Nim syntax |

The NimScript approach means the pipeline IS Nim code — no separate parser needed. The `nimo` binary just wraps the standard NimScript executor with the pipeline API injected.

## Open Questions

- Where does the pipeline API live? (`nimo` binary injects it, or a separate `.nim` module?)
- How do we handle long context windows? (chunking? RAG?)
- Should there be a visual DAG editor?
- Error handling: what happens if one node fails? Retry? Skip?
- Should pipelines be cached? (skip re-running nodes whose inputs haven't changed)
