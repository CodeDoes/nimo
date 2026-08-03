# 0001 — Vision

NIMO is an AI Harness — deterministic software wrapping non-deterministic LLM inference.

## Core Principles

1. **System Instruction** — Immutable rules anchored at top of context
2. **Tool Calls** — Model outputs structured requests, harness executes
3. **Agentic** — Human-in-the-loop with steering, interrupting, resuming
4. **Planning** — Explicit task decomposition with state tracking
5. **Sub-Agents** — Hierarchical delegation for complex tasks
6. **Workload Contexts** — Different configs for chat vs creative

## Architecture

```
┌─────────────────────────────────────────┐
│  User (CLI/TUI)                         │
├─────────────────────────────────────────┤
│  Harness (nimo)                         │
│  ├─ Session Manager (message tree)      │
│  ├─ Tool Dispatcher (pipeline, bash)    │
│  ├─ Context Window Manager              │
│  ├─ Checkpoint/Resume                   │
│  └─ Workload Config (chat/story)        │
├─────────────────────────────────────────┤
│  Model (RWKV-7)                         │
└─────────────────────────────────────────┘
```

## Workload Modes

| Mode | Temp | Context | Tools | Use Case |
|------|------|---------|-------|----------|
| Chat | 0.0-0.3 | Aggressive pruning | Full | Conversational |
| Story | 0.7-1.0 | Global continuity | Memory retrieval | Long-form creative |
| Pipeline | 0.5-0.7 | Step-by-step | File I/O | Multi-step tasks |

## Session Format

JSONL tree structure (see [1000-session.md](1000-session.md)).

## See Also

- [1000-session.md](1000-session.md) — session data model
- [3000-pipeline.md](3000-pipeline.md) — pipeline tool
- [9100-logging.md](9100-logging.md) — JSONL logging
