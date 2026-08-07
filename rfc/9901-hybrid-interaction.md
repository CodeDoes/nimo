# RFC 9901 — Hybrid Interaction Model

**Status:** conceptual design
**Category:** 2 — CLI / User Interface

## The Hierarchy

Three layers, each produces the next:

```
/plan "goal"     ──► produces / DSL script
/ DSL script     ──► when run, produces > NL context
> NL context     ──► fed to model → produces | response
```

## Full Interaction

```
/                           <- plan DSL mode (produced by /plan)
  generate format(
    ("Current Time", current_time())
    ("Recent Sessions", recall "recent sessions")
    ("User Profile", recall "user profile")
    ("Instructions", "A simple greeting")
  )
>                           <- natural language mode (produced by running /)
  Recent Sessions:
  - Session 1: ...
  - Session 2: ...
  
  User Profile:
  name: Alice
  likes: poetry
  
  Instructions:
  A simple greeting
|                           <- output boundary (produced by model)
  Hello there! Last night was wild wasn't it!
```

## How It Works

1. **User types** `/plan "write a greeting"`
2. **Agent produces** the `/` DSL script (structured context assembly)
3. **User runs** `/run` (or presses Enter)
4. **DSL executes** — assembles context from time, memory, literals
5. **Context becomes** the `>` natural language block
6. **Model generates** the `|` response from that context

## Syntax

| Symbol | Mode | Produced by |
|--------|------|-------------|
| `/` | Plan DSL | `/plan` command |
| `>` | Natural language | DSL execution (context assembly) |
| `|` | Output | Model generation |

## Example: Greeting

```
/plan "write a greeting"
▶ produce plan
  / generate format(
      ("Time", current_time())
      ("User", recall "profile")
      ("Instructions", "friendly greeting")
    )

/ run
▶ execute
  > It's morning. User likes poetry.
  > Write a friendly greeting.
  |
  Good morning! The dawn brings new possibilities.
```

## Example: Story Generation

```
/plan "write a short story about a lighthouse"
▶ produce plan
  / generate format(
      ("Premise", "lighthouse keeper finds message in bottle")
      ("Tone", "melancholy")
      ("Length", "short")
    )

/ run
▶ execute
  > Premise: lighthouse keeper finds message in bottle
  > Tone: melancholy — lonely, reflective, hint of hope
  > Length: short (300-500 words)
  |
  The bottle bobbed against the rocks like a lost child...
```

## Why This Matters

- **Transparent** — you see each layer: plan, context, response
- **Editable** — can edit any layer before execution
- **Debuggable** — can inspect context before generation
- **Hierarchical** — each layer produces the next

## Implementation

The plan script, when executed, assembles context and passes it to generate:

```nim
proc executeDSL(script: string): string =
  # Parse the / script
  let parts = parseDSL(script)
  
  # Assemble context (the > part)
  var context = ""
  for (label, expr) in parts:
    let value = evaluate(expr)  # current_time(), recall(), literal
    context.add(label & ": " & value & "\n")
  
  # Generate response (the | part)
  return generate(context)
```

## Relationship to Existing DSL

This doesn't replace `structured()` — it **wraps** it:

```
# Existing (flat)
let response = structured Response "context: ..."

# Hybrid (hierarchical)
/ generate format(("Context", recall "profile"))
> Context: ...
| Response...
```

The hybrid mode makes the context assembly **visible** and **editable**.
