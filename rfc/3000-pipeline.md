# Pipeline DSL

NimScript DSL for multi-step LLM pipelines. Run with `nim script pipeline.nim`.

## Core DSL

```nim
import std/[os, strutils, tables]

type PipelineNode = ref object
  id: string
  output: string

proc generate(prompt: string, target: string = ""): PipelineNode = discard
proc extract(src: PipelineNode, filter: string): PipelineNode = discard
proc summarize(src: PipelineNode, length: string = "brief"): PipelineNode = discard
```

## Execution Model

- Downstream nodes wait for dependencies (topological sort)
- Parallel execution of independent nodes is optional
- Each node runs `nim script` and captures stdout to `output`
- `target` writes output to file

## Pipeline Types

| # | Type | RFC | Description |
|---|------|-----|-------------|
| 3110 | chat | [3110-chat.md](3110-chat.md) | Interactive chat with tool calls, think blocks |
| 3111 | story | [3111-story.md](3111-story.md) | Multi-chapter story generation |
| 3112 | workspace | [3112-workspace.md](3112-workspace.md) | Workspace management operations |
| 3113 | agent | [3113-agent.md](3113-agent.md) | Autonomous agent actions |

## Open

- Cache: skip nodes whose inputs haven't changed
- Context window: chunking or RAG for large outputs
- Error handling: retry or abort?

## See Also

- [2000-cli.md](2000-cli.md) — intent extraction produces pipeline.nim
- [4000-config.md](4000-config.md) — pipeline uses config for model params
- [3110-chat.md](3110-chat.md)
- [3111-story.md](3111-story.md)
- [3112-workspace.md](3112-workspace.md)
- [3113-agent.md](3113-agent.md)
