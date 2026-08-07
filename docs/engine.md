# The DSL Is the Engine

## Core Insight

The nimo DSL **is** nimo-chat's engine. Not a wrapper, not a plugin — the foundation.

```
┌─────────────────────────────────────────┐
│          nimo-chat (interactive)        │
│  ┌───────────────────────────────────┐  │
│  │   DSL Engine (the loop)           │  │
│  │  structured() → for → if → save   │  │
│  │                                   │  │
│  │  + custom code:                   │  │
│  │    - readline loop                │  │
│  │    - steer/queue/inbox            │  │
│  │    - _ convention                 │  │
│  │    - /plan command                │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## What This Means

| Surface | How it works |
|---------|--------------|
| **Interactive chat** | DSL loop + readline + steer/queue |
| **Plan execution** | DSL loop (autonomous) |
| **Workflow** | DSL loop (from file) |
| **One-shot** | DSL loop (single step) |

Same engine, different driver.

## The Loop

```nim
proc runDSL(script: string): void =
  for step in compile(script):
    case step.kind
    of structured:
      let output = generate(step.prompt)
      bind(step.variable, parse(step.schema, output))
    of for:
      for item in step.items:
        runDSL(step.body)  # recursive!
    of if:
      if check(step.condition):
        runDSL(step.then)
      else:
        runDSL(step.else)
    of save:
      writeFile(step.path, getVariable(step.variable))
    of say:
      echo step.text
```

**Chat adds:**
- Readline loop (get user input)
- Steer/queue inbox (inject during execution)
- `_` convention (last result)
- `/plan` command (produce script from goal)

## Why This Matters

1. **One codebase** — no separate "chat engine" and "plan engine"
2. **Debuggable** — step through the DSL like any script
3. **Extensible** — add new step types, extend the loop
4. **Transparent** — what you see is what runs

## The Custom Layer

The "custom code" is thin:

```nim
# Chat driver (custom)
while true:
  let input = readLine()
  if input.startsWith("/"):
    handleCommand(input)
  else:
    let plan = producePlan(input)
    runDSL(plan)  # same engine!
```

The engine doesn't know it's being driven by chat. It just runs steps.

## Implications

- **Workflows ARE chat** — just saved to file
- **Plans ARE chat** — just produced from `/plan`
- **Chat IS workflows** — just interactive

No special cases. One loop.
