# 3000 — Pipeline

Pipeline is a tool the model can call. Steps are injected into the session.

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
                           [nimo] ✔ 10/10 (45.2s)
                           Artifacts: wiki/max.md, chapters/01.md"
messages[5] (think): "Pipeline complete. I should summarize the results."
messages[6] (text): "Here's your cyberpunk story! Check wiki/max.md and chapters/01.md"
```

## Interrupt / Resume

User presses Ctrl+C during execution. Pipeline state saved:

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
