# 3000 — Pipeline

Pipeline is a tool the model can call for multi-step work.

## Tool Call

```
<tool_call>{"tool": "run_pipeline", "intent": "Write a cyberpunk story about Max"}</tool_call>
```

## Tool Result

```
<tool_result>
[nimo] ▶ 1/10 Generating wiki: Max...
→ wiki/max.md
[nimo] ✔ 1/10 (0.8s)
[nimo] ▶ 2/10 Generating wiki: Rob...
→ wiki/rob.md
[nimo] ✔ 2/10 (0.7s)
...
[nimo] ✔ 10/10 (45.2s)
Artifacts: wiki/max.md, chapters/01.md, outline.md
</tool_result>
```

## Session Storage

Pipeline execution is stored as a tool_call + tool_result pair:

```jsonl
{"ts":"...","msg_id":5,"kind":"tool_call","content":"run_pipeline: Write a cyberpunk story about Max"}
{"ts":"...","msg_id":5,"kind":"tool_result","content":"[nimo] ▶ 1/10..."}
```

## Interrupt / Resume

User can interrupt with Ctrl+C. Pipeline state is saved to disk:

```
~/.ws/myproject/.nimo/pipeline_{id}.json
```

Resume with:
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
- [3100-chat.md](3100-chat.md) — chat integration
