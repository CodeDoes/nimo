# 9100 — Logging

JSONL files. **Status: implemented** in `src/session_manager.nim` (sessions) and `src/pipeline.nim` (pipeline reports).

## Example log line

```jsonl
{"ts":"2024-01-01T00:00:00","type":"message_part","part":"user","content":"Hello"}
{"ts":"2024-01-01T00:00:01","type":"message_part","part":"think","content":"User greeted me"}
{"ts":"2024-01-01T00:00:02","type":"message_part","part":"text","content":"Hi!"}
{"ts":"2024-01-01T00:00:03","type":"stats","tokens":12,"ms":340}
```

## Files

```
logs/
  sessions/   {session_id}.jsonl
  pipelines/  {pipeline_id}.jsonl
```

Each pipeline run gets its own JSONL file with step-by-step trace.
