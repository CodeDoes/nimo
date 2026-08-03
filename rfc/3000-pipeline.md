# 3000 — Pipeline DSL

NimScript-style DSL for multi-step LLM workflows.

## Procs

```nim
proc generate(prompt: string, target: string = ""): PipelineNode
proc extract(src: PipelineNode, filter: string): PipelineNode
proc summarize(src: PipelineNode, length: string = "brief"): PipelineNode
```

## Example: Story Generation

```nim
import std/[os, strutils]

type PipelineNode = ref object
  id: string
  output: string

# Generate wiki entries (parallel)
let max_wiki    = generate("Generate character: Max, robot ninja", target = "wiki/max.md")
let rob_wiki    = generate("Generate character: Rob, heavy ordnance", target = "wiki/rob.md")
let boss_wiki   = generate("Generate villain: Ghastone", target = "wiki/boss.md")
let city_wiki   = generate("Generate setting: Neo-Kuroba", target = "wiki/city.md")

# Extract context (depends on wiki)
let max_ctx = extract(max_wiki, "combat, gear, personality")
let rob_ctx = extract(rob_wiki, "equipment, tactics")

# Generate chapters (sequential with context)
let ch1 = generate(
  """
  World: $#{city_wiki}
  Character: $#{max_ctx}
  Task: Write Chapter 1
  """,
  target = "chapters/01.md"
)

let ch1_recap = summarize(ch1, length = "bullet_points")

let ch2 = generate(
  """
  Previous: $#{ch1_recap}
  Partner: $#{rob_ctx}
  Task: Write Chapter 2
  """,
  target = "chapters/02.md"
)
```

## Execution

- Upstream nodes run first
- Downstream nodes wait for dependencies
- Parallel execution for independent nodes (optional)
- `target` writes output to file

## See Also

- [3100-chat.md](3100-chat.md) — chat pipeline example
- [3200-story.md](3200-story.md) — story pipeline example
- [3300-workspace.md](3300-workspace.md) — workspace pipeline example
