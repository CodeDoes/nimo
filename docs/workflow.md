# Workflow

A workflow is a **saved plan** — a sequential Nim script that uses inference to perform a function.

## What It Is

```nim
# A workflow is just a plan you save and reuse
let outline = structured StoryOutline "create a story for: " & premise
save "outline.json", outline

for char in outline.characters:
    let wiki = structured CharacterWiki "wiki for: " & char
    save "wikis/" & char & ".json", wiki
```

## Properties

| Property | What it means |
|----------|---------------|
| **Sequential** | Steps run in order |
| **Uses inference** | Calls `structured()` to generate content |
| **Easy to monitor** | Each step shows ▶ or ✔ |
| **Easy to edit** | Plain Nim script, editable in any editor |
| **Easy to write** | Same DSL as interactive plans |

## Lifecycle

```
1. Write    → /edit or create from template
2. Monitor  → /run shows progress step-by-step
3. Edit     → Fix issues, re-run
4. Save     → Store for reuse
5. Run      → Execute anytime
```

## Examples

### Simple Workflow
```nim
# docs/examples/01-simple-generate.md
let haiku = structured Haiku "write a haiku about AI"
save "haiku.md", haiku
```

### Story Workflow
```nim
# docs/examples/06-story-pipeline.md
let outline = structured StoryOutline "..."
save "outline.json", outline

for char in outline.characters:
    let wiki = structured CharacterWiki "..." & char
    save "wikis/" & char & ".json", wiki
```

### Data Pipeline Workflow
```nim
let raw = load "input.json"
let transformed = structured Transform "..." & raw
save "output.json", transformed
```

## Why "Workflow" and Not "Plan"

- **Plan** = produced by `/plan "goal"` (one-off)
- **Workflow** = saved plan you reuse (persistent)

Same DSL, different purpose.

## Storage

```
.nimo/workflows/
  story.md        # Story generation workflow
  haiku.md        # Haiku generation workflow
  transform.md    # Data transformation workflow
```

Each workflow is a `.md` file with the Nim script.

## Run a Workflow

```
nimo> /run .nimo/workflows/story.md
▶ produce plan from file
▶ run
▶ generate
  ...
```

Or just edit and run:

```
nimo> /edit .nimo/workflows/story.md
# ... modify ...
nimo> /run
▶ run
▶ generate
  ...
```

## Key Insight

A workflow is just a **reusable script**. No magic. No visual editor. Just Nim code that calls the model.
