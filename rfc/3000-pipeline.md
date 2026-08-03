# 3000 — Pipeline

Pipeline is a tool the model can call. Supports interruption and adjustment.

## Session Flow

```
user -> pipeline -> root.chat
user -> pipeline -> pipeline.relavent-story.relavent-chapter.write
pipeline.report -> user
user -> pipeline -> pipeline.story.summarize
pipeline.report -> user
...
```

## Example Session

```jsonl
{"type":"session","version":3,"id":"...","timestamp":"...","cwd":"/home/kit/dev/nimo"}
{"type":"message","id":"msg1","parentId":null,"message":{"role":"user","content":[{"type":"text","text":"Write a cyberpunk story"}]}}
{"type":"message","id":"msg2","parentId":"msg1","message":{"role":"assistant","content":[{"type":"thinking","thinking":"Creating pipeline..."},{"type":"toolCall","id":"call1","name":"run_pipeline","arguments":{"intent":"write story"}}],"stopReason":"toolUse"}}
{"type":"message","id":"msg3","parentId":"msg2","message":{"role":"toolResult","toolCallId":"call1","toolName":"run_pipeline","content":[{"type":"text","text":"[nimo] ▶ 1/10 Generating wiki: Max...\n[nimo] ✔ 1/10 (0.8s)\n[nimo] ▶ 2/10 Generating wiki: Rob...\n[nimo] ✔ 2/10 (0.7s)"}],"isError":false}}
{"type":"message","id":"msg4","parentId":"msg3","message":{"role":"assistant","content":[{"type":"text","text":"Story in progress..."}]}}
{"type":"message","id":"msg5","parentId":"msg4","message":{"role":"user","content":[{"type":"text","text":"Actually, make it sci-fi instead"}]}}
{"type":"message","id":"msg6","parentId":"msg5","message":{"role":"assistant","content":[{"type":"thinking","thinking":"User changed direction. Adjusting pipeline..."},{"type":"toolCall","id":"call2","name":"run_pipeline","arguments":{"intent":"rewrite as sci-fi"}}],"stopReason":"toolUse"}}
{"type":"message","id":"msg7","parentId":"msg6","message":{"role":"toolResult","toolCallId":"call2","toolName":"run_pipeline","content":[{"type":"text","text":"[nimo] ▶ 1/8 Generating wiki: Max (sci-fi)...\n[nimo] ✔ 1/8 (0.9s)"}],"isError":false}}
```

## Interruption

User can interrupt anytime by sending a new message:
- Current pipeline step is aborted
- Agent adjusts based on new input
- New pipeline starts (or continues from checkpoint)

## Checkpoint / Resume

Ctrl+C saves state:
```
~/.ws/myproject/.nimo/pipeline_{id}.json
```

Resume:
```
nimo resume {pipeline_id}
```

## Workspace Artifacts

```
~/.ws/myproject/
  wiki/
    max.md
  chapters/
    01.md
  summary.md
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
