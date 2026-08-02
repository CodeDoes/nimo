## What is this file for?

NimScript DSL for multi-step LLM pipelines. Run with `nim script pipeline.nim`.

## Example

```nim
import std/[os, strutils, tables]

type PipelineNode = ref object
  id: string
  output: string

proc generate(prompt: string, target: string = ""): PipelineNode = discard
proc extract(src: PipelineNode, filter: string): PipelineNode = discard
proc summarize(src: PipelineNode, length: string = "brief"): PipelineNode = discard

# ── Pipeline ──

let max_wiki    = generate("Generate character entry for Max: robot ninja.",     target = "wiki/max.md")
let rob_wiki    = generate("Generate character entry for Rob: heavy ordnance.",  target = "wiki/rob.md")
let boss_wiki   = generate("Generate character entry for Ghastone: crime boss.", target = "wiki/boss.md")
let city_wiki   = generate("Generate world entry for Neo-Kuroba: cyberpunk city.", target = "wiki/city.md")

let max_ctx = extract(max_wiki, "combat abilities, gear, personality")
let rob_ctx = extract(rob_wiki, "equipment, tactics, background")

let ch1 = generate(
  """
  World: $#{city_wiki}
  Character: $#{max_ctx}
  Task: Write Chapter 1 — Max operating solo in Neo-Kuroba.
  """,
  target = "chapters/01.md"
)

let ch1_recap = summarize(ch1, length = "bullet_points")

let ch2 = generate(
  """
  Previous: $#{ch1_recap}
  Partner: $#{rob_ctx}
  Task: Write Chapter 2 — introduce Rob as Max's partner.
  """,
  target = "chapters/02.md"
)

let draft = generate(
  """
  Progress: $#{ch1_recap}
  Antagonist: $#{boss_wiki}
  Task: Draft plot beats for chapters 4–10, ending in Ghastone's defeat.
  """,
  target = "draft_outline.md"
)

let ch2_recap = summarize(ch2, length = "bullet_points")

let ch3 = generate(
  """
  Previous: $#{ch2_recap}
  Task: Write Chapter 3 — Max and Rob uncover Ghastone's operations.
  """,
  target = "chapters/03.md"
)

let ch3_recap = summarize(ch3, length = "bullet_points")

generate(
  """
  Endpoint: $#{ch3_recap}
  Outline: $#{draft}
  Task: Finalize outline for chapters 4–10.
  """,
  target = "outline.md"
)
```

## Execution

Parallel execution of independent nodes is optional (nice-to-have).
Parallel execution of independent nodes is optional (nice-to-have).
## Open

- Cache: skip nodes whose inputs haven't changed
- Context window: chunking or RAG for large outputs
- Error handling: retry or abort?
