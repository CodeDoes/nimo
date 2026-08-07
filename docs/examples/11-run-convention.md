# The _ Convention (REPL-style)

Like Nim's REPL, `_` is implicitly set to the last plan produced.

## Core Workflow

```
/plan "goal"      → produces plan, stores in _, shows it (does NOT execute)
/run              → executes _ (last plan)
/run _            → same, explicit
/approve          → same, semantic
Enter             → same, fastest
/run 3            → resume from step 3
/edit             → edit _ in editor
/discard          → clear _
```

## Example

```
nimo> /plan "write a haiku"
▶ produce plan
  let haiku = structured Haiku "..."
  
nimo> /run _        # explicit
▶ generate
  wrote 47 bytes -> haiku.md
  
nimo> /plan "write a poem"
▶ produce plan
  let poem = structured Poem "..."
  
nimo> /run          # runs the last plan (poem, not haiku)
▶ generate
  ...
  
nimo> /approve      # same as /run
▶ generate
  ...
  
nimo> Enter         # also runs last plan
▶ generate
  ...
```

## Commands Reference

| Command | What it does |
|---------|--------------|
| `/plan "<goal>"` | Produce a plan from goal, store in `_` |
| `/run` | Execute `_` (last plan) |
| `/run _` | Same as `/run` (explicit) |
| `/run 3` | Resume execution from step 3 |
| `/approve` | Same as `/run` (semantic) |
| `/edit` | Open `_` in editor for modification |
| `/discard` | Clear `_`, no execution |
| `Enter` | Same as `/run` (fastest) |

## State Machine

```
                    ┌──────────────┐
                    │              │
                    ▼              │
/plan "goal" ──► [_ = plan] ──► /run ──► execute
                    │
                    ├──► /edit ──► modify _ ──► /run
                    │
                    ├──► /discard ──► _ = null
                    │
                    └──► /run 3 ──► resume from step 3
```

## Why `_` Matters

1. **No typing**: Just press Enter to run
2. **Explicit when needed**: `/run _` makes intent clear
3. **Inspectable**: `/edit` lets you modify before running
4. **Resumable**: `/run 3` lets you continue from a point
5. **Clean**: `/discard` clears state when done

## Common Workflow

```
nimo> /plan "write a story"
▶ produce plan
  ...
  
nimo> /edit         # Review and modify
  # Changed 2 steps
  
nimo> /run          # Execute modified plan
▶ generate
  ...
  
nimo> /discard      # Clear for next plan
nimo>
```
