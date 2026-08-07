# Example 8: Debugging a Plan

Find and fix errors in your plan before running.

## The Problem

```nim
# User pastes a plan and wants to see what's happening

let outline = structured StoryOutline "..."
# ^-- cursor here, inspect:
# outline = null (not yet generated)

save "outline.json", outline
# ^-- error: outline is null, can't save
```

## User Sees

```
nimo> /plan "..."
▶ produce plan
  let outline = structured StoryOutline "..."
  save "outline.json", outline
  
nimo> /run
▶ generate
  outline = null  # ERROR: nothing to save
  write failed: content is empty
nimo>
```

## The Fix

```nim
# Generate first, then save
outline = structured StoryOutline "..."
say "outline generated: " & outline.acts.len & " acts"
save "outline.json", outline
```

## Debug Output

```
nimo> /run
▶ generate
  outline.acts = ["beginning", "middle", "end"]
▶ outline generated: 3 acts
▶ save
  wrote 412 bytes -> outline.json
nimo>
```

## Debugging Techniques

### 1. Inspect Variables

```
nimo> outline
null  # Not generated yet!

nimo> /run  # Run to this point
▶ generate
nimo> outline
{...}  # Now it exists
```

### 2. Use say() for Checkpoints

```nim
say "before generate"
let x = structured Schema "..."
say "after generate: " & x.someField
```

Output:
```
before generate
after generate: value
```

### 3. Run Step-by-Step

```
nimo> /run 1      # Run just step 1
nimo> outline     # Inspect
nimo> /run 2      # Run step 2
nimo> outline     # Inspect again
```

### 4. Edit and Re-run

```
nimo> /edit       # Open plan in editor
# Fix the plan
nimo> /run        # Run the fixed plan
```

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `null` variable | Generated before assignment | Add generate step first |
| `write failed` | Empty content | Check validation before save |
| `schema mismatch` | Wrong output shape | Fix schema or prompt |
| `loop empty` | List is empty | Check source data |

## Why This Matters

- **Fail fast**: Errors caught before execution
- **Inspect mid-plan**: See variable state at any point
- **Step-by-step**: Run one step at a time to isolate issues
- **Editable**: Fix and re-run without starting over
