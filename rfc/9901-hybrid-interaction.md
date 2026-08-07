# RFC 9901 — Hybrid Interaction Model

**Status:** conceptual design
**Category:** 2 — CLI / User Interface

## The Idea

A hybrid interaction model that blends structured DSL with natural language:

```
/                           <- plan DSL mode (structured)
  generate format(
    ("Current Time", current_time())
    ("Recent Sessions", recall "recent sessions")
    ("User Profile", recall "user profile")
    ("Instructions", "A simple greeting")
  )
>                           <- natural language mode (prose)
  Recent Sessions:
  - Session 1: ...
  - Session 2: ...
  
  User Profile:
  name: Alice
  likes: poetry
  
  Instructions:
  A simple greeting
|                           <- output boundary
  Hello there! Last night was wild wasn't it!
```

## Syntax

| Symbol | Mode | Purpose |
|--------|------|---------|
| `/` | Plan DSL | Structured context assembly |
| `>` | Natural language | Prose context, instructions |
| `|` | Output | Model response boundary |

## How It Works

1. **Start with `/`** — enter plan DSL mode
2. **Assemble context** — use `generate format(...)` to gather structured data
3. **Switch to `>`** — enter natural language mode for prose context
4. **Add instructions** — natural language guidance for the model
5. **Output appears at `|`** — model response

## Why This Matters

- **Best of both worlds** — structured context + natural language framing
- **Transparent** — you can see exactly what context was assembled
- **Editable** — mix DSL and prose in the same plan
- **Debuggable** — see context before generation

## Example: Greeting Workflow

```
/
  generate format(
    ("Time", current_time())
    ("User", recall "user profile")
    ("Context", "A friendly greeting")
  )
>
  It's morning. The user likes poetry.
  Write a greeting that references the time of day.
|
  Good morning! The dawn brings new possibilities.
```

## Example: Story Generation

```
/
  generate format(
    ("Premise", "A lighthouse keeper discovers a message in a bottle")
    ("Tone", "melancholy")
    ("Length", "short")
  )
>
  Write a short story about a lighthouse keeper who finds a message in a bottle.
  The tone should be melancholy — lonely, reflective, with a hint of hope.
|
  The bottle bobbed against the rocks like a lost child...
```

## Implementation

This would be a new input mode in `chat.nim`:

```nim
# Pseudo-code for the hybrid parser
proc parseHybrid(input: string): Plan =
  var lines = input.splitLines()
  var plan = newPlan()
  
  for line in lines:
    if line.startsWith("/"):
      # Plan DSL mode
      plan.add(parseDSL(line))
    elif line.startsWith(">"):
      # Natural language mode
      plan.addContext(line[1..].strip())
    elif line.startsWith("|"):
      # Output boundary (already generated)
      plan.output = line[1..].strip()
  
  return plan
```

## Relationship to Existing DSL

This doesn't replace `structured()` — it **wraps** it:

```nim
# Existing (pure DSL)
let response = structured Response "context: ..."

# Hybrid (DSL + natural language)
/
  generate format(
    ("Context", recall "user profile")
  )
>
  Write a friendly greeting.
|
  Hello there!
```

The hybrid mode is sugar on top of the same engine.

## Questions

1. **Is this needed?** Or is `structured()` + natural language prompts enough?
2. **Where does this live?** In `chat.nim`? As a new input mode?
3. **How does it interact with `/plan`?** Can you produce a hybrid plan?

## Next Steps

If this is valuable:
1. Add to RFC 2111 as a new input mode
2. Implement in `chat.nim`
3. Add examples to `docs/examples/`
