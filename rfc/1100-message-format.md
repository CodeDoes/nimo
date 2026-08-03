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

```
Assistant: 
<tool_call>{"name": "run_pipeline", "arguments": {"intent": "Write a story"}}</tool_call>
```

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
