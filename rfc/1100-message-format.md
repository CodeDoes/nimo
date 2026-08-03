# 1100 — Message Format

Raw text format for each part type. Shows the complete assistant response flow.

## Complete Response Flow

```
Assistant: 
[think block]
[text OR tool_call]
```

Think ALWAYS comes first. Then either text OR tool_call (not both).

## Example: Think → Text

```
User: What is 2+2?

Assistant: 
The user is asking a simple math question.
2 + 2 equals 4.
```

## Example: Think → Tool Call

```
User: What's the weather in Boston?

Assistant: 
I need to call the weather tool.
<tool_call>{"get_weather": {"location": "Boston, MA"}}</tool_call>

User: <tool_result>72°F, sunny</tool_result>

Assistant: 
The weather in Boston is 72°F and sunny.
```

## Example: Text Only (no think)

```
User: Hello!

Assistant: Hi there! How can I help?
```

## Example: Multi-Tool Call

```
Assistant: 
I'll check both cities.
<tool_call>[{"get_weather": {"location": "Boston"}}, {"get_weather": {"location": "NYC"}}]</tool_call>

User: <tool_result>[{"location":"Boston","temp":"72°F"},{"location":"NYC","temp":"68°F"}]</tool_result>

Assistant: 
Boston is 72°F and NYC is 68°F.
```

## Part Types Summary

| Part | Format | Context |
|------|--------|---------|
| `system` | `System: ...` | Always first, primes the model |
| `user` | `User: ...` | User input or tool result |
| `think` | `` | Before text or tool_call |
| `tool_call` | `<tool_call>...</tool_call>` | After think, requests tool execution |
| `tool_result` | `<tool_result>...</tool_result>` | Injected by NIMO after tool runs |
| `text` | (plain text) | After think or tool_result |

## See Also

- [1000-session.md](1000-session.md) — session data model
