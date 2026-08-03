# 3200 — Story Pipeline

Multi-chapter story generation with wiki context.

## Example Flow

```
User: "Write a cyberpunk story about robot ninja Max"

Pipeline:
  1. Generate wiki for each character/world (parallel)
  2. Extract context from wiki (parallel)
  3. Generate Chapter 1 with wiki context
  4. Summarize Chapter 1
  5. Generate Chapter 2 with Ch1 recap + character context
  6. ...
  7. Finalize outline
```

## Pipeline Example

```nim
# Phase 1: Wiki generation (parallel)
let max_wiki    = generate("Character: Max, robot ninja",     target = "wiki/max.md")
let rob_wiki    = generate("Character: Rob, heavy ordnance",  target = "wiki/rob.md")
let city_wiki   = generate("Setting: Neo-Kuroba cyberpunk",   target = "wiki/city.md")

# Phase 2: Context extraction (parallel)
let max_ctx = extract(max_wiki, "combat, gear, personality")
let rob_ctx = extract(rob_wiki, "equipment, tactics")

# Phase 3: Chapters (sequential)
let ch1 = generate(
  "World: $#{city_wiki}\nCharacter: $#{max_ctx}\nWrite Chapter 1",
  target = "chapters/01.md"
)
let ch1_recap = summarize(ch1, length = "bullet_points")

let ch2 = generate(
  "Previous: $#{ch1_recap}\nPartner: $#{rob_ctx}\nWrite Chapter 2",
  target = "chapters/02.md"
)
```

## Output Structure

```
myproject/
  wiki/
    max.md
    rob.md
    city.md
  chapters/
    01.md
    02.md
    ...
  outline.md
```

## See Also

- [3000-pipeline.md](3000-pipeline.md) — pipeline DSL
- [5000-workspace.md](5000-workspace.md) — workspace layout
