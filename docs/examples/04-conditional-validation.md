# Example 4: Conditional Validation

Check output quality and revise if needed.

## User Input

```
nimo> /plan "write chapter 1 and validate"
```

## The Plan

```nim
let outline = load "outline.json"
let chapter = structured Chapter "write chapter 1 about: " & outline.acts[0]

if chapter.wordCount < 500:
    let revised = structured Chapter "revise chapter 1 (too short): " & chapter.content
    save "chapter1.md", revised.content
else:
    save "chapter1.md", chapter.content

say "chapter 1 " & (if chapter.wordCount >= 500: "passed" else: "revised")
```

## What Happens

1. **Generate**: Create chapter from outline
2. **Validate**: Check word count (>= 500 required)
3. **Conditional**: If failed, generate revision
4. **Save**: Write final chapter

## User Sees

```
nimo> /plan "write chapter 1 and validate"
▶ produce plan
  if chapter.wordCount < 500:
      ... (revision logic)
      
nimo> /run
▶ generate
  validate: words=312 paras=3 quality=fail
▶ generate (revision)
  validate: words=547 paras=6 quality=pass
▶ chapter 1 revised
nimo>
```

## The Validation Check

```nim
proc validate(chapter: Chapter): bool =
  chapter.wordCount >= 500 and
  chapter.paragraphCount >= 5 and
  chapter.repeatingSegments == 0
```

This is **deterministic** — no model needed. Just math.

## What the Engine Executes

```
Step 1: skGenerate
  context: "write chapter 1 about: the discovery"
  output: {"content": "...", "wordCount": 312, ...}
  
Step 2: skValidate (implicit)
  text: from step 1
  result: fail (wordCount < 500)
  
Step 3: skGenerate (revision)
  context: "revise chapter 1 (too short): ..." + chapter.content
  output: {"content": "...", "wordCount": 547, ...}
  
Step 4: skWrite
  path: "chapter1.md"
  content: from step 3
```

## Why This Matters

- **Self-correcting**: Plans can fix their own mistakes
- **Deterministic gates**: Validation is fast, no model cost
- **Visible failures**: You see exactly why something failed
- **Revision prompts**: The revision prompt includes the original output

## Common Validation Patterns

```nim
# Word count gate
if chapter.wordCount < 500:
    chapter = structured Chapter "revise (too short): " & chapter.content

# Quality gate
if not validate(chapter):
    chapter = structured Chapter "fix quality: " & chapter.content

# Schema gate
if not check(chapter, ChapterSchema):
    chapter = structured Chapter "fix schema: " & chapter.content
```
