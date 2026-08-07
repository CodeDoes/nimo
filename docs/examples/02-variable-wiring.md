# Example 2: Variable Wiring

Connecting variables together — output of one step becomes input to the next.

## User Input

```
nimo> /plan "create a story outline about a lighthouse"
```

## The Plan

```nim
let premise = "a lighthouse keeper discovers a message in a bottle"
let outline = structured StoryOutline "create a story outline for: " & premise
save "outline.json", outline
```

## Variable Flow

```
premise ──┐
          ├─► generate ──► outline ──► save
premise ──┘
```

1. `premise` ← literal string (user-provided)
2. `outline` ← generated from `premise`
3. File ← saved from `outline`

## User Sees

```
nimo> /plan "create a story outline about a lighthouse"
▶ produce plan
  let premise = "a lighthouse keeper discovers a message in a bottle"
  let outline = structured StoryOutline "create a story outline for: " & premise
  save "outline.json", outline
  
nimo> /run
▶ generate
  wrote 412 bytes -> outline.json
nimo>
```

## Inspect Variables

You can inspect any variable at any time:

```
nimo> outline.premise
"a lighthouse keeper discovers a message in a bottle"

nimo> outline.acts
["The keeper finds the bottle", "The message reveals a secret", "The keeper must decide"]

nimo> outline.characters
["Keeper", "Stranger", "Child"]
```

## What the Engine Executes

```
Step 1: skGenerate
  context: "create a story outline for: a lighthouse keeper discovers a message in a bottle"
  skill: "StoryOutline"
  output: {"premise": "...", "acts": [...], "characters": [...]}
  
Step 2: skWrite
  path: "outline.json"
  content: from step 1
  output: "wrote 412 bytes -> outline.json"
```

## String Concatenation

The `&` operator joins variables and literals:

```nim
let prompt = "create a story outline for: " & premise
```

Becomes:
```
"create a story outline for: a lighthouse keeper discovers a message in a bottle"
```

## Why This Matters

- **Variables are first-class**: Named, inspectable, reusable
- **No magic**: You can see exactly what each variable contains
- **Composable**: Output of one step feeds input to next
- **Debuggable**: Inspect mid-plan to see what happened
