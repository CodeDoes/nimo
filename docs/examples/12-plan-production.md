# How Plans Are Produced

When you type `/plan "goal"`, here's what happens:

## Step 1: Intent Matching

```nim
proc matchIntent(goal: string): Intent =
  let g = goal.toLowerAscii()
  if g.contains("poem"): itPoem
  elif g.contains("chapter"): itChapter
  elif g.contains("remember") or g.contains("note"): itMemory
  elif g.contains("story") or g.contains("tale"): itStory
  else: itAnswer
```

## Step 2: Plan Template Selection

Each intent has a pre-built plan template:

```nim
proc buildPlan(intent: Intent, goal: string): Plan =
  case intent
  of itStory:
    result.addStep(extractStep("pull-context", "memory", "the story so far"))
    result.addStep(generateStep("draft-story", goal, "output:story"))
    result.addStep(writeStep("save-story", "story.md"))
    result.addStep(reportStep("story written"))
  of itPoem:
    result.addStep(generateStep("write-poem", goal, "output:poem"))
    result.addStep(writeStep("save-poem", "poem.md"))
    result.addStep(reportStep("poem written"))
  # ... more templates
```

## Step 3: Emission (Future)

Once the learned planner is integrated:

```nim
proc interpret(goal: string): Plan =
  # Current: deterministic template
  return buildPlan(matchIntent(goal), goal)
  
  # Future: model produces plan
  # let emission = generate("produce plan for: " & goal)
  # return compileEmission(emission, goal)
```

## User Sees

```
nimo> /plan "write a haiku about AI"
▶ produce plan
  let haiku = structured Haiku "write a haiku about AI"
  save "haiku.md", haiku
  say "done"
  
  # Plan has 3 steps. Ready to run.
nimo>
```

## What "Produce" Means

1. **Parse** the goal into intent
2. **Select** the plan template
3. **Format** as Nim-script
4. **Store** in `_`
5. **Display** for review
6. **Do NOT execute**

## The Separation

| Phase | Command | What happens |
|-------|---------|--------------|
| Produce | `/plan "goal"` | Compile goal → plan script |
| Execute | `/run` | Run plan script → output |

This is like `nim check` vs `nim run`:
- `check` = compile, show errors, don't run
- `run` = execute

## Why Two Phases?

1. **Review**: See what will happen before it happens
2. **Edit**: Modify the plan if needed
3. **Safety**: No surprise executions
4. **Transparency**: You can inspect the plan

## Future: Learned Planner

Currently, plans are template-based (deterministic). Future: the model itself will produce plans:

```nim
# Future
let emission = generate("produce plan for: " & goal)
let plan = compileEmission(emission, goal)
```

But the produce-then-run separation stays the same.
