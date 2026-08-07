# Example 5: Memory & Recall

Store context once, reuse it later.

## User Input

```
nimo> /plan "remember this and summarize later"
```

## The Plan

```nim
memory "User prefers concise answers, under 3 sentences"
# ... some conversation ...
let summary = structured Summary "summarize preferences: " & recall("preferences")
save "prefs.md", summary
```

## What Happens

1. **Store**: `memory` writes to the memory store (persistent across turns)
2. **Later**: `recall` reads from the store
3. **Generate**: Use recalled context in a generate call
4. **Save**: Write result

## User Sees

```
nimo> /plan "remember this and summarize later"
▶ produce plan
  memory "User prefers concise answers, under 3 sentences"
  let summary = structured Summary "summarize preferences: " & recall("preferences")
  
nimo> /run
▶ memory store updated
▶ generate
  wrote 89 bytes -> prefs.md
nimo>
```

## Memory Store

```
nimo> recall("preferences")
"User prefers concise answers, under 3 sentences"

nimo> recall("all")
[
  "User prefers concise answers, under 3 sentences",
  "User likes stories about lighthouses",
  "User is working on a novel"
]
```

## Memory Operations

| Operation | What it does |
|-----------|--------------|
| `memory "<text>"` | Append to memory store |
| `recall("<key>")` | Get by key |
| `recall("all")` | Get everything |
| `memory.clear()` | Clear store |

## Why This Matters

- **Cross-turn context**: Remember things across /plan calls
- **User preferences**: Store once, use everywhere
- **Workspace context**: Remember workspace state
- **No prompt bloat**: Don't repeat context in every prompt

## Common Patterns

```nim
# Store user preference
memory "User wants responses under 100 words"

# Use in later plan
let summary = structured Summary "be concise: " & recall("preferences")

# Store workspace state
memory "Current workspace: /home/user/project"

# Recall for context
let plan = structured Plan "consider: " & recall("workspace")
```
