# 1100 — Message Format

Raw text format for each content type.

## Text

```
Hi there! How can I help?
```

## Thinking

```
Assistant: 
I should respond politely.
Hi there! How can I help?
```

## Tool Call

The model is prompted to emit the `[tool]` line form. Small RWKV models often
emit the others, so the harness parses **all three** (see `src/harness.nim`,
`parseToolCalls`):

### 1. `[tool]` line (preferred)

```
[tool] run_pipeline {"intent": "write a poem about roses"}
```

### 2. `<tool_call>` JSON tag

```
<tool_call>{"name": "run_pipeline", "arguments": {"intent": "Write a story"}}</tool_call>
```

### 3. Bare JSON object line (fallback)

```json
{"name": "run_pipeline", "arguments": {"intent": "Write a story"}}
{"tool": "run_pipeline", "arguments": {"intent": "Write a story"}}
{"arguments": {"intent": "Write a story"}}            // implied run_pipeline
```

Any unrecognized non-JSON text around the call is kept as natural language
(`stripToolCallText`).

## Tool Result

```
User: <tool_result>[nimo] ▶ 1/10... ✔ 1/10...</tool_result>

Assistant: 
```

## Multi-Tool Call

```
Assistant: 
<tool_call>[{"name": "tool1", "arguments": {...}}, {"name": "tool2", "arguments": {...}}]</tool_call>
```

## See Also

- [1000-session.md](1000-session.md) — session data model (JSON format)
