# 1000 — Session

A session is a conversation between user and model. It tracks messages and allows branching.

## Data Model

```nim
Session = object
  messages: seq[Message]
  branches: seq[Branch]      # alternative conversation paths
  activeBranch: int          # current branch index

Message = object
  kind: MessageKind          # user, think, text, tool_call, tool_result, system
  content: string
```

## Message Types

Each message is ONE type:

| Type | Description |
|------|-------------|
| `system` | Primes the model (always first) |
| `user` | User input |
| `think` | Model's thinking (hidden from user) |
| `text` | Model's text response |
| `tool_call` | Model requests a tool |
| `tool_result` | Tool output (injected by NIMO) |

## Example: Simple Chat

```
messages[0] (system): "You are helpful"
messages[1] (user):   "Hello"
messages[2] (think):  "I should respond"
messages[3] (text):   "Hi! How can I help?"
```

## Example: Tool Call

```
messages[0] (user):   "What's the weather?"
messages[1] (think):  "I need to call the weather tool"
messages[2] (tool_call): "get_weather(Boston)"
messages[3] (tool_result): "72°F, sunny"
messages[4] (text):   "It's 72°F and sunny in Boston"
```

## Example: Multi-Tool Call

```
messages[0] (user):   "Weather in Boston and NYC?"
messages[1] (think):  "I'll check both cities"
messages[2] (tool_call): "get_weather(Boston), get_weather(NYC)"
messages[3] (tool_result): "Boston: 72°F, NYC: 68°F"
messages[4] (text):   "Boston is 72°F and NYC is 68°F"
```

## See Also

- [1100-message-format.md](1100-message-format.md) — raw text format for each message type
