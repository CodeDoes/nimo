# Example 6: Full Story Pipeline

A complete story generation pipeline with outline, characters, chapters.

## User Input

```
nimo> /plan "write a 3-chapter story"
```

## The Plan

```nim
# Setup
let premise = "a lighthouse keeper discovers a message in a bottle"

# Outline
let outline = structured StoryOutline "create a story outline for: " & premise
save "outline.json", outline

# Characters
for char in outline.characters:
    let wiki = structured CharacterWiki "write wiki entry for: " & char
    save "wikis/" & char & ".json", wiki

# Chapters
for i in 1..3:
    let act = outline.acts[i-1]
    let chapter = structured Chapter "write chapter " & $i & " about: " & act
    if chapter.wordCount < 500:
        chapter = structured Chapter "revise chapter " & $i & " (needs more): " & chapter.content
    save "chapters/ch" & $i & ".md", chapter.content

say "story complete: " & $outline.characters.len & " chars, 3 chapters"
```

## User Sees

```
nimo> /plan "write a 3-chapter story"
▶ produce plan
  # 18 steps, 2 loops
  
nimo> /run
▶ generate
  wrote 412 bytes -> outline.json
▶ loop: characters (4 items)
  ▶ generate
    wrote 623 bytes -> wikis/Alex.json
  ▶ generate
    wrote 445 bytes -> wikis/Maya.json
  ▶ generate
    wrote 534 bytes -> wikis/Sam.json
  ▶ generate
    wrote 389 bytes -> wikis/Lennox.json
▶ loop: chapters (3 items)
  ▶ generate
    validate: words=487 quality=fail
  ▶ generate (revision)
    validate: words=612 quality=pass
    wrote 612 bytes -> chapters/ch1.md
  ▶ generate
    validate: words=534 quality=pass
    wrote 534 bytes -> chapters/ch2.md
  ▶ generate
    validate: words=423 quality=fail
  ▶ generate (revision)
    validate: words=589 quality=pass
    wrote 589 bytes -> chapters/ch3.md
▶ story complete: 4 chars, 3 chapters
nimo>
```

## What the Engine Executes

```
Outline Phase:
  Step 1: skGenerate - create outline
  Step 2: skWrite - save outline.json

Character Phase:
  Step 3-6: skGenerate - 4 character wikis
  Step 7-10: skWrite - 4 wiki files

Chapter Phase:
  Step 11: skGenerate - chapter 1
  Step 12: skValidate - check chapter 1 (fail)
  Step 13: skGenerate - revise chapter 1
  Step 14: skValidate - check revision (pass)
  Step 15: skWrite - save chapter 1
  ... (repeat for chapters 2-3)

Final:
  Step 18: skReport - "story complete: 4 chars, 3 chapters"
```

## File Structure Created

```
outline.json          # 412 bytes
wikis/
  Alex.json           # 623 bytes
  Maya.json           # 445 bytes
  Sam.json            # 534 bytes
  Lennox.json         # 389 bytes
chapters/
  ch1.md              # 612 bytes (revised)
  ch2.md              # 534 bytes
  ch3.md              # 589 bytes (revised)
```

## Why This Matters

- **End-to-end pipeline**: One plan, multiple phases
- **Self-correcting**: Chapters that fail validation get revised
- **Structured output**: Each phase produces predictable artifacts
- **Inspectable**: You can inspect any variable at any point

## Common Pipeline Patterns

```nim
# Generate → Validate → Save (with revision)
let x = structured Schema "prompt"
if not validate(x):
    x = structured Schema "revise: " & x
save "path", x

# Loop with fan-out
for item in list:
    let child = structured ChildSchema "process: " & item
    save "output/" & item.id & ".json", child

# Chain with dependency
let a = structured A "first"
let b = structured B "from: " & a
let c = structured C "from: " & b
save "final.json", c
```
