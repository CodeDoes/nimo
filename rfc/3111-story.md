# Story Pipeline

Multi-chapter story generation pipeline.

## Example Flow

```
User: "Write a cyberpunk story about robot ninja Max and his partner Rob"
  → Extract characters, world, plot
  → Generate wiki for each entity
  → Extract context buffers
  → Generate Chapter 1 (with wiki context)
  → Summarize Ch1
  → Generate Chapter 2 (with Ch1 recap + partner context)
  → Summarize Ch2
  → Generate Chapter 3
  → Draft outline for Ch4-10
  → Finalize outline
```

## Pipeline Structure

```nim
# Phase 1: Entity extraction
let max_wiki    = generate("Generate character entry for Max: robot ninja.",     target = "wiki/max.md")
let rob_wiki    = generate("Generate character entry for Rob: heavy ordnance.",  target = "wiki/rob.md")
let boss_wiki   = generate("Generate character entry for Ghastone: crime boss.", target = "wiki/boss.md")
let city_wiki   = generate("Generate world entry for Neo-Kuroba: cyberpunk city.", target = "wiki/city.md")

# Phase 2: Context extraction (parallel)
let max_ctx = extract(max_wiki, "combat abilities, gear, personality")
let rob_ctx = extract(rob_wiki, "equipment, tactics, background")

# Phase 3: Chapter generation (sequential with recap)
let ch1 = generate("World: #{city_wiki}\nCharacter: #{max_ctx}\nTask: Write Chapter 1", target = "chapters/01.md")
let ch1_recap = summarize(ch1, length = "bullet_points")

let ch2 = generate("Previous: #{ch1_recap}\nPartner: #{rob_ctx}\nTask: Write Chapter 2", target = "chapters/02.md")
let ch2_recap = summarize(ch2, length = "bullet_points")

let ch3 = generate("Previous: #{ch2_recap}\nTask: Write Chapter 3", target = "chapters/03.md")

# Phase 4: Outline
let outline = generate("Endpoint: #{ch3_recap}\nTask: Finalize outline for chapters 4-10", target = "outline.md")
```

## Parallel Groups

- Wiki generation: all 4 can run in parallel
- Context extraction: depends on wiki, runs after
- Chapter generation: sequential (each needs previous recap)
- Outline: depends on latest chapter

## See Also

- [3000-pipeline.md](3000-pipeline.md) — core DSL
- [2000-cli.md](2000-cli.md) — example in intent flow
