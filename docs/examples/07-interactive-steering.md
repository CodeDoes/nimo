# Example 7: Interactive Steering

Redirect an ongoing turn without interrupting mid-generation.

## User Input

```
nimo> /send "write a poem about roses"
```

## What Happens

```
nimo> /send "write a poem about roses"
▶ generate
  wrote 89 bytes -> poem.md
nimo>
```

The user gets a poem. But they want it darker.

## Steering

```
nimo> /steer "make it darker, more gothic"
▶ generate (steer injected at boundary)
  wrote 102 bytes -> poem.md
nimo>
```

**Steer does NOT interrupt the in-flight generation.** It waits for the current step to complete, then injects the new directive before the next step.

## Queueing for Later

```
nimo> /queue "also add a second stanza" on-finish
queued (1 pending)
nimo> /quit
# "also add a second stanza" runs on next startup
```

## What the Engine Executes

```
Turn 1:
  Step 1: skGenerate
    context: "write a poem about roses"
    output: "... (89 bytes)"
    
Step 2: skWrite
  path: "poem.md"
  
Turn 2 (steer):
  Step 3: skGenerate
    context: "make it darker, more gothic" + previous context
    output: "... (102 bytes)"
    
Step 4: skWrite
  path: "poem.md"
  
Turn 3 (queued, next session):
  Step 5: skGenerate
    context: "also add a second stanza"
```

## Steering Semantics

| Command | When valid | What it does |
|---------|------------|--------------|
| `/send "<text>"` | idle | Start new turn |
| `/steer "<text>"` | busy | Inject at next boundary |
| `/queue "<text>"` | any | Hold for later |
| `/flush` | any | Run queued immediately |

## Why This Matters

- **Non-blocking**: You can steer while the model is thinking
- **Boundary-safe**: Never mid-generation, always at step boundary
- **Queued actions**: Plan ahead, execute later
- **Human-in-the-loop**: You stay in control

## Common Steering Patterns

```
# Redirect mid-conversation
nimo> /send "write about cats"
▶ generate
nimo> /steer "no, dogs instead"
▶ generate (redirected)

# Queue a follow-up
nimo> /queue "also write about birds" on-finish
nimo> /quit
# Next session starts with "also write about birds"

# Emergency stop
nimo> /steer "stop, this is wrong"
▶ generate (aborting)
```
