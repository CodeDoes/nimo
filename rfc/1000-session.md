# 1000 — Session

A session is a conversation between user and model. It tracks messages and allows branching.

## Data Model

```nim
Session = object
  messages: seq[Message]
  branches: seq[Branch]      # alternative conversation paths
  activeBranch: int          # current branch index

Message = object
  parts: seq[Part]           # ordered sequence of parts

Part = object
  kind: PartKind             # system, user, think, tool_call, tool_result, text
  content: string
```

## Example

```
Session:
  messages[0]:
    part[0] (system): "You are helpful"
    part[1] (user):   "Hello"
    part[2] (think):  "I should respond"
    part[3] (text):   "Hi!"
  messages[1]:
    part[0] (user):   "What's the weather?"
    part[1] (tool_call): "get_weather(Boston)"
    part[2] (tool_result): "72°F"
    part[3] (text):   "It's sunny"
```

## See Also

- [1100-message-format.md](1100-message-format.md) — raw text format for each part type
