# Example 3: Loop with Fan-out

Generate multiple outputs from a list — one per item.

## User Input

```
nimo> /plan "generate character wikis from outline"
```

## The Plan

```nim
let outline = load "outline.json"
for char in outline.characters:
    let wiki = structured CharacterWiki "write wiki entry for: " & char
    save "wikis/" & char & ".json", wiki
say "wikis complete"
```

## What Happens

1. **Load**: Read `outline.json` into `outline` variable
2. **Loop**: Iterate over `outline.characters`
3. **Generate**: For each character, generate a wiki entry
4. **Save**: Write each wiki to `wikis/<name>.json`

## User Sees

```
nimo> /plan "generate character wikis from outline"
▶ produce plan
  for char in outline.characters:
      let wiki = structured CharacterWiki "write wiki entry for: " & char
      save "wikis/" & char & ".json", wiki
      
nimo> /run
▶ loop: characters (4 items)
  ▶ generate
    wrote 623 bytes -> wikis/Alex.json
  ▶ generate
    wrote 445 bytes -> wikis/Maya.json
  ▶ generate
    wrote 534 bytes -> wikis/Sam.json
  ▶ generate
    wrote 389 bytes -> wikis/Lennox.json
▶ wikis complete
nimo>
```

## What the Engine Executes

```
Step 1: skLoop (implicit)
  items: outline.characters = ["Alex", "Maya", "Sam", "Lennox"]
  
Step 2-5: skGenerate (one per item)
  char = "Alex"
    context: "write wiki entry for: Alex"
    output: {...}
  char = "Maya"
    context: "write wiki entry for: Maya"
    output: {...}
  ...
  
Step 6-9: skWrite (one per item)
  path: "wikis/Alex.json", content: from step 2
  path: "wikis/Maya.json", content: from step 3
  ...
```

## Loop Semantics

- `for x in list:` iterates over each item
- Each iteration runs the body independently
- Variables from previous iterations don't leak (unless explicitly saved)
- The loop itself is an `skLoop` step that splices sub-plans

## Why This Matters

- **One loop, many generates**: No need to write 4 separate plans
- **Data-driven**: The list comes from previous output
- **Parallelizable**: Each iteration is independent (could run in parallel)
- **Scalable**: Works for 3 items or 300 items
