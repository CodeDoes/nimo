# Trace

## Purpose

Track execution flow for debugging and observability.

## Trace Points

- Pipeline node entry/exit
- Tool call dispatch
- Think block parsing
- Workspace operations
- Model eval timing

## Trace Format

```
[timestamp] [level] [module] [trace_point] [details]
```

## Current Implementation

`src/macros.nim` — `benchmarkStep` macro logs timing to eternal log.

## RFC Scope

- Structured trace format
- Trace collector (in-memory buffer)
- Trace export (JSON, text)
- Performance profiling integration
