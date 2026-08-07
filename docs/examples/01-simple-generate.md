# Example 1: Simple Generate

The most basic plan: one generate step, one save step.

## User Input

```
nimo> /plan "write a haiku about AI"
```

## The Plan (produced, not run yet)

```nim
let haiku = structured Haiku "write a haiku about AI"
save "haiku.md", haiku
say "done"
```

## What Happens Internally

1. **Parse**: Agent reads the plan script
2. **Generate**: Calls `Generate("write a haiku about AI")` with schema `Haiku`
3. **Model Output**: `{"lines": ["bits of light", "thinking in silicon", "quiet minds"], "wordCount": 5}`
4. **Validate**: Parser checks against `Haiku` schema (3 lines, ~5-7-5 syllables)
5. **Bind**: Result stored in `haiku` variable
6. **Write**: File written to disk
7. **Report**: "done" printed

## User Sees

```
nimo> /plan "write a haiku about AI"
▶ produce plan
  let haiku = structured Haiku "write a haiku about AI"
  save "haiku.md", haiku
  say "done"
  
  # Plan stored in _. 9 steps. Ready to run.
nimo> /run
▶ generate
  wrote 47 bytes -> haiku.md
▶ done
nimo>
```

## What the Engine Executes

```
Step 1: skGenerate
  context: "write a haiku about AI"
  skill: "Haiku"
  output: "{\"lines\": [\"bits of light\", \"thinking in silicon\", \"quiet minds\"], \"wordCount\": 5}"
  
Step 2: skWrite
  path: "haiku.md"
  content: from step 1 output
  output: "wrote 47 bytes -> haiku.md"
  
Step 3: skReport
  title: "done"
  output: "done"
```

## Schema Definition

```nim
type Haiku* = object
  lines*: seq[string]
  wordCount*: int
```

The schema tells the parser what shape to expect. If the model outputs invalid JSON or wrong shape, validation fails immediately.

## Why This Matters

- **One primitive**: `structured` is all you need
- **Variables are explicit**: `haiku` is a named slot you can inspect
- **Schema validation**: Wrong shape = error, not silent failure
- **Trace is visible**: Every step shows what happened
