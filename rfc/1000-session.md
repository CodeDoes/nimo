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

## Message Structure

Each message has parts in this order:

```
user → think → text → (tool_call + tool_result) → system
```

## Example: Simple Chat

```
Message:
  part[0] (user):   "Hello"
  part[1] (think):  "I should respond"
  part[2] (text):   "Hi! How can I help?"
```

## Example: Tool Call

```
Message:
  part[0] (user):   "What's the weather?"
  part[1] (think):  "I need to call the weather tool"
  part[2] (tool_call): "get_weather(Boston)"
  part[3] (tool_result): "72°F, sunny"
  part[4] (text):   "It's 72°F and sunny in Boston"
```

## Example: Multi-Tool Call

```
Message:
  part[0] (user):   "Weather in Boston and NYC?"
  part[1] (think):  "I'll check both cities"
  part[2] (tool_call): "get_weather(Boston), get_weather(NYC)"
  part[3] (tool_result): "Boston: 72°F, NYC: 68°F"
  part[4] (text):   "Boston is 72°F and NYC is 68°F"
```

## See Also

- [1100-message-format.md](1100-message-format.md) — raw text format for each part type
