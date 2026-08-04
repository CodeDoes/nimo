# 3400 — Agent

The harness agent loop. **Status: implemented** in `src/harness.nim`.

## What it is

The harness is the "agent mode": instead of a one-shot answer, the model can
call tools and continue working until it has a final answer. The loop is:

```
user -> generate -> tool_call? -> execute -> feed result back -> generate -> ... -> final text
```

## How a turn works (step by step)

### 1. Build the prompt

The user's message is wrapped with a system prompt (`HarnessSystemPrompt`)
that explains the `run_pipeline` tool and shows an example of the exact
`[tool]` line format the model must emit.

### 2. Generate a reply

The model produces text (up to the max tokens for this turn).

### 3. Parse tool calls

The reply is scanned for tool calls in **three** formats (see
[1100-message-format.md](1100-message-format.md)):

1. `[tool] run_pipeline {...}` lines
2. `<tool_call>{...}</tool_call>` blocks
3. bare JSON object lines like `{"name": ..., "arguments": ...}`

### 4. Branch on the result

- **No tool call** → the reply is natural text. It is recorded as the final
  answer and the turn ends.
- **Tool call(s) found** → for each call:
  1. Record the call as a message (role assistant, stopReason `toolUse`).
  2. Run the tool (`executeTool` looks up the name in the session's registry;
     `run_pipeline` is the one registered by the harness).
  3. Record the result as a message (role toolResult, parented to the call).
  4. Collect the results into a feedback block.
  - Then strip tool markers from the reply, keep any natural text, append the
    feedback, and go back to step 2 ("Now answer the user's question...").

### 5. Iteration guard

The loop runs at most **8 iterations** (`MaxToolIterations`). If the model
keeps calling tools and never gives a final answer, the turn is marked
`aborted = true` and stops — no infinite loop.

## Session bookkeeping

- The user message, tool calls, tool results, and final text are all recorded
  in the session message tree (see [1000-session.md](1000-session.md)).
- `/save <file>` writes the whole session as JSONL.
- After each turn the harness prints the number of iterations and any tool
  calls, plus the wall-clock time.

## Offline mode

With `-d:harnessOffline`, no model is loaded: the session uses a scripted
generator (`genStub`) so the loop, parsing, and evals run without rwkv.cpp.

## See Also

- [3000-pipeline.md](3000-pipeline.md) — the tool the loop executes
- [1100-message-format.md](1100-message-format.md) — parsing the 3 formats
- [1000-session.md](1000-session.md) — the message tree
