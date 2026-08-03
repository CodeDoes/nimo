# 3000 — Pipeline

Pipeline is a tool the harness executes. Supports interruption, steering, resume.

## Tool Call

```json
{"type":"toolCall","id":"call_xxx","name":"run_pipeline","arguments":{"intent":"Write a story"}}
```

## Tool Result

```json
{"type":"toolResult","toolCallId":"call_xxx","toolName":"run_pipeline","content":[{"type":"text","text":"[nimo] ▶ 1/10... ✔ 1/10..."}],"isError":false}
```

## Interruption

User sends new message mid-pipeline:
```jsonl
{"type":"message","role":"user","content":[{"type":"text","text":"Actually, make it sci-fi"}]}
```

Harness:
1. Aborts current pipeline step
2. Updates context with new intent
3. Creates new pipeline (or adjusts existing)
4. Continues execution

## Steering

Inject guidance without clearing state:
```json
{"type":"message","role":"system","content":[{"type":"text","text":"User updated priority: focus on speed over accuracy"}]}
```

## Resume

Checkpoint saved on interrupt/Ctrl+C:
```
~/.ws/myproject/.nimo/pipeline_{id}.json
```

Resume:
```bash
nimo resume {pipeline_id}
```

## Pipeline DSL

```nim
proc generate(prompt: string, target: string = ""): PipelineNode
proc extract(src: PipelineNode, filter: string): PipelineNode
proc summarize(src: PipelineNode, length: string = "brief"): PipelineNode
```

## Planning & State Tracking

Pipeline tracks explicit state:
```
Pending: [step1, step2, step3]
In-Progress: [step2]
Completed: [step1]
Failed: []
```

Feeds back to context each iteration.

## Sub-Agents

Parent pipeline can delegate to child pipelines:
```nim
let child = run_pipeline("sub-task", parent = parent_pipeline)
```

Child runs isolated, returns summarized result.

## Workload Contexts

| Mode | Temp | Context | Tools |
|------|------|---------|-------|
| Chat | 0.0-0.3 | Aggressive pruning | Full |
| Story | 0.7-1.0 | Global continuity | Memory retrieval |
| Pipeline | 0.5-0.7 | Step-by-step | File I/O |

## See Also

- [1000-session.md](1000-session.md) — session data model
- [9100-logging.md](9100-logging.md) — JSONL logging
- [9200-trace.md](9200-trace.md) — trace output
