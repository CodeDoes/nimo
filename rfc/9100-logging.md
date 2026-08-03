# Logging

## Log Levels

- `trace` — detailed execution flow (pipeline steps, token counts)
- `debug` — model loading, tokenization, sampling details
- `info` — session start, generation complete, errors
- `warn` — missing files, deprecated features
- `error` — failures, exceptions

## Log Targets

- `logs/eternal.log` — append-only, never truncated
- `logs/session-{timestamp}.log` — per-session detailed log
- stderr — real-time progress for CLI/TUI

## Current Implementation

`src/logger.nim` — basic append-to-file with session start, generation, chat entries.

## RFC Scope

- Log format spec (structured JSON vs plain text)
- Log rotation policy
- Per-workspace log isolation
- Log aggregation for pipelines
