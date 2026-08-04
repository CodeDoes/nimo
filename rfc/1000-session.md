# 1000 — Session

The conversation model. **Status: implemented** in `src/session_manager.nim`.

## What a session is

A session is the full conversation: a list of messages, each with an id, a
parent id (forming a tree), a timestamp, a role, content parts, and a stop
reason. The harness builds this tree as it talks to the model.

## Data model (as coded)

```nim
Session = ref object
  id: string            # "sess_20260729..."
  timestamp: string
  cwd: string
  messages: seq[Message]
  branches: seq[string]       # branch ids (see session_branch.nim)
  activeBranch: int
  tools: Table[string, ToolHandler]  # registered tools
  # (online builds also carry model, tokenizer, state, logits, rng)

Message = object
  id: string            # "msg_0", "msg_1", ...
  parentId: string      # links this message to its parent (tree)
  timestamp: string
  role: MessageRole     # user | assistant | toolResult
  content: seq[ContentPart]
  stopReason: string    # "stop" | "toolUse"

ContentPart = object
  kind: ContentKind     # text | thinking | toolCall | toolResult
  text: string
  toolCallId: string    # links a toolResult to its toolCall
  toolName: string
  arguments: string
  thinkingSignature: string
```

## How a turn builds the tree (step by step)

1. The user message is recorded: `addText(userMsg)` → `msg0` (role user).
2. The model replies. If the reply contains a tool call, it is recorded with
   `addToolCall(name, args, parentId)` → `msg1` (role assistant,
   stopReason `toolUse`), parented to `msg0`.
3. The tool runs. Its result is recorded with `addToolResult(...)` → `msg2`
   (role toolResult), parented to the tool call `msg1`.
4. The model is asked to continue. Its natural-text answer is recorded via
   `addText(reply, parentId)` → `msg3` (role assistant), parented to `msg2`.

The chain looks like:

```
msg0 (user)
  └─ msg1 (assistant, toolCall: run_pipeline)
       └─ msg2 (toolResult)
            └─ msg3 (assistant, text)   <- final answer
```

## Saving to disk

`saveSession(path)` writes one JSON object per line (JSONL):

1. First line: the session header `{"type":"session","version":3,"id":...,"cwd":...}`.
2. One line per message, with role, parentId, content parts, and stopReason.

This is what the evals check: header + a user → toolCall → toolResult → text
chain with correct parent ids.

## Branching

Alternative conversation paths live in `src/session_branch.nim` (see
[0006 plan](../plan/0006-session-branching.md)): a session can fork into
branches, each with its own id, parent message, and timestamp.

## See Also

- [1100-message-format.md](1100-message-format.md) — how tool calls appear in text
- [3400-agent.md](3400-agent.md) — the loop that builds this tree
- [3000-pipeline.md](3000-pipeline.md) — the tool that gets called
