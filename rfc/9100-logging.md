# Logging

JSONL files for each message part. Structured, append-only.

## Format

```jsonl
{"timestamp":"2024-01-01T00:00:00","type":"session_start","app":"chat","model":"/path/to/model.bin"}
{"timestamp":"2024-01-01T00:00:01","type":"message_part","part_type":"system","content":"You are a helpful assistant"}
{"timestamp":"2024-01-01T00:00:02","type":"message_part","part_type":"user","content":"Hello"}
{"timestamp":"2024-01-01T00:00:03","type":"message_part","part_type":"think","content":"I should respond politely"}
{"timestamp":"2024-01-01T00:00:04","type":"message_part","part_type":"text","content":"Hi there! How can I help?"}
{"timestamp":"2024-01-01T00:00:05","type":"generation_stats","tokens":42,"elapsed_ms":1234}
```

## Files

- `logs/sessions/{session_id}.jsonl` — one file per session
- `logs/pipelines/{pipeline_id}.jsonl` — one file per pipeline run
- `logs/tools/{tool_name}.jsonl` — one file per tool type

## Current Implementation

`src/logger.nim` — append-to-file with session/generation/chat entries.
