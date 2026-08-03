# 1000 — Session

Session is a tree of messages with harness management.

## Data Model

```nim
Session = object
  id: string
  timestamp: string
  cwd: string
  parentSession: string         # optional, for branching
  messages: seq[Message]
  branches: seq[Branch]         # alternative conversation paths
  activeBranch: int

Message = object
  id: string
  parentId: string
  timestamp: string
  role: MessageRole             # user, assistant, toolResult
  content: seq[ContentPart]
  usage: Usage                  # tokens, cost
  stopReason: StopReason        # toolUse, stop, aborted

ContentPart = object
  kind: ContentKind             # text, thinking, toolCall, toolResult
  text: string
  toolCallId: string            # for toolCall/toolResult linking
  toolName: string              # for toolCall
  arguments: string             # for toolCall
  thinkingSignature: string     # for thinking
```

## Message Tree

```
msg1 (user)
  └─ msg2 (assistant) — toolCall: run_pipeline
       └─ msg3 (toolResult) — result of run_pipeline
            └─ msg4 (assistant) — text response
                 └─ msg5 (user) — "Actually, make it sci-fi"
                      └─ msg6 (assistant) — toolCall: run_pipeline (adjusted)
```

## Harness Responsibilities

1. **Context Window Management** — Trim old messages, keep system anchored
2. **Tool Dispatch** — Execute tool calls, append results
3. **Checkpointing** — Save state for interrupt/resume
4. **Steering** — Inject guidance without clearing state

## See Also

- [1100-message-format.md](1100-message-format.md) — raw text format
- [3000-pipeline.md](3000-pipeline.md) — pipeline tool
