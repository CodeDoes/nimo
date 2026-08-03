# 3000 — Pipeline

Pipeline is a tool the model can call. Steps produce artifacts in workspace, not session.

## Session Flow

```
messages[0] (system): "You are helpful"
messages[1] (user): "Write a cyberpunk story about Max"
messages[2] (think): "I should create a pipeline..."
messages[3] (tool_call): "run_pipeline: Write a cyberpunk story"
messages[4] (tool_result): "[nimo] ▶ 1/10 Generating wiki: Max...
                           [nimo] ✔ 1/10 (0.8s)
                           [nimo] ▶ 2/10 Generating wiki: Rob...
                           [nimo] ✔ 2/10 (0.7s)
                           ...
                           [nimo] ✔ 10/10 (45.2s)"
messages[5] (think): "Pipeline complete. Let me read the artifacts."
messages[6] (text): "Your story is ready! Check wiki/max.md and chapters/01.md"
```

## Pipeline Context

Each pipeline step defines what context it produces:

```nim
let max_wiki = generate("Generate character: Max", target = "wiki/max.md")
let max_ctx = extract(max_wiki, "combat, gear, personality")
```

- `target` writes to workspace file
- `extract` pulls specific content into pipeline context
- Context is isolated — not injected into session

## Session Stay Clean

Session only contains:
- `tool_call`: "run_pipeline: intent"
- `tool_result`: trace output (progress + completion)

Actual artifacts stay in workspace:
```
~/.ws/myproject/
  wiki/max.md
  chapters/01.md
  outline.md
```

## Interrupt / Resume

Ctrl+C saves pipeline state:
```
~/.ws/myproject/.nimo/pipeline_{id}.json
```

Resume:
```
nimo resume {pipeline_id}
```

## Pipeline DSL

```nim
proc generate(prompt: string, target: string = ""): PipelineNode
proc extract(src: PipelineNode, filter: string): PipelineNode
proc summarize(src: PipelineNode, length: string = "brief"): PipelineNode
```

## See Also

- [1000-session.md](1000-session.md) — session data model
- [9100-logging.md](9100-logging.md) — JSONL logging
- [9200-trace.md](9200-trace.md) — trace output
- [3200-story.md](3200-story.md) — story pipeline example
