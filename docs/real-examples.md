# Real Examples — How the Nim-script DSL Actually Works

## Example 1: Simple Generate

```nim
# User types: /plan "write a haiku about AI"

let haiku = structured Haiku "write a haiku about AI"
save "haiku.md", haiku
say "done"
```

**What happens:**
1. Agent parses the plan
2. Runs `Generate("write a haiku about AI")` with schema `Haiku`
3. Model outputs: `{"lines": ["bits of light", "thinking in silicon", "quiet minds"], "wordCount": 5}`
4. Parser validates against `Haiku` schema (3 lines, ~5-7-5 syllables)
5. Binds to `haiku` variable
6. Writes to `haiku.md`
7. Prints "done"

**User sees:**
```
nimo> /plan "write a haiku about AI"
▶ generate
  wrote 47 bytes -> haiku.md
▶ done
nimo>
```

---

## Example 2: Variable Wiring

```nim
# User types: /plan "create a story outline about a lighthouse"

let premise = "a lighthouse keeper discovers a message in a bottle"
let outline = structured StoryOutline "create a story outline for: " & premise
save "outline.json", outline
```

**Variables flow:**
- `premise` ← literal string
- `outline` ← generated from `premise`
- File ← saved from `outline`

**User can inspect at any point:**
```
nimo> let premise = "..."
nimo> let outline = structured StoryOutline "..." & premise
nimo> # inspect
nimo> outline.premise
"..."
nimo> outline.characters
["Keeper", "Stranger", "Child"]
```

---

## Example 3: Loop with Fan-out

```nim
# User types: /plan "generate character wikis from outline"

let outline = load "outline.json"
for char in outline.characters:
    let wiki = structured CharacterWiki "write wiki entry for: " & char
    save "wikis/" & char & ".json", wiki
say " wikis complete"
```

**Engine trace:**
```
▶ loop: characters (3 items)
  ▶ generate: "write wiki entry for: Keeper"
    wrote 847 bytes -> wikis/Keeper.json
  ▶ generate: "write wiki entry for: Stranger"
    wrote 623 bytes -> wikis/Stranger.json
  ▶ generate: "write wiki entry for: Child"
    wrote 412 bytes -> wikis/Child.json
▶ wikis complete
```

---

## Example 4: Conditional Validation

```nim
# User types: /plan "write chapter 1 and validate"

let outline = load "outline.json"
let chapter = structured Chapter "write chapter 1 about: " & outline.acts[0]

if chapter.wordCount < 500:
    let revised = structured Chapter "revise chapter 1 (too short): " & chapter.content
    save "chapter1.md", revised.content
else:
    save "chapter1.md", chapter.content

say "chapter 1 " & (if chapter.wordCount >= 500: "passed" else: "revised")
```

**User sees:**
```
▶ generate
  validate: words=312 paras=3 quality=fail
▶ generate (revision)
  validate: words=547 paras=6 quality=pass
▶ chapter 1 revised
```

---

## Example 5: Memory & Recall

```nim
# User types: /plan "remember this and summarize later"

memory "User prefers concise answers, under 3 sentences"
# ... some conversation ...
let summary = structured Summary "summarize preferences: " & recall("preferences")
save "prefs.md", summary
```

**Memory store:**
```
nimo> recall("preferences")
"User prefers concise answers, under 3 sentences"
```

---

## Example 6: Real Story Pipeline

```nim
# User types: /plan "write a 3-chapter story"

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

**Full trace:**
```
nimo> /plan "write a 3-chapter story"
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
```

---

## Example 7: Interactive Steering

```
nimo> /send "write a poem about roses"

▶ generate
  wrote 89 bytes -> poem.md
nimo> /steer "make it darker, more gothic"

▶ generate (steer injected at boundary)
  wrote 102 bytes -> poem.md
nimo> /queue "also add a second stanza" on-finish
nimo> /quit
# "also add a second stanza" runs on next startup
```

---

## Example 8: Debugging a Plan

```nim
# User pastes a plan and wants to see what's happening

let outline = structured StoryOutline "..."
# ^-- cursor here, inspect:
# outline = null (not yet generated)

save "outline.json", outline
# ^-- error: outline is null, can't save

# Fix: generate first
outline = structured StoryOutline "..."
say "outline generated: " & outline.acts.len & " acts"
```

**Debug output:**
```
▶ generate
  outline.acts = ["beginning", "middle", "end"]
▶ outline generated: 3 acts
▶ save
  wrote 412 bytes -> outline.json
```

---

## Example 9: Model-as-Judge Eval

```nim
# User types: /model-eval --scored --trials 3

# Internally:
let scenarios = @[
    StructuredScenario("friendly", "I had a rough day", friendliness),
    StructuredScenario("concise", "What is the capital of France?", conciseness)
]

for s in scenarios:
    let sample = structured s.schema s.prompt
    let score = judge sample, s.metric
    save "eval/results.json", score
```

---

## Key Patterns

### Pattern 1: Generate → Validate → Save
```nim
let x = structured Schema "prompt"
if check(x):
    save "path", x
else:
    let y = structured Schema "revise: " & x
    save "path", y
```

### Pattern 2: Loop over List
```nim
for item in list:
    let child = structured ChildSchema "process: " & item
    save "output/" & item.id & ".json", child
```

### Pattern 3: Chain Variables
```nim
let a = structured A "..."
let b = structured B "from: " & a
let c = structured C "from: " & b
save "final.json", c
```

### Pattern 4: Memory Injection
```nim
memory "important context"
# ... later ...
let result = structured Result "consider: " & recall("important context")
```

---

## What Makes This Work

1. **Variables are inspectable** — you can `say` or `inspect` any variable at any point
2. **Schema validation catches errors early** — wrong shape = error, not silent failure
3. **Plans are editable** — paste, modify, re-run
4. **Streaming is visible** — each step shows ▶ or ✔
5. **Steer is boundary-safe** — never mid-generation, always at step boundary

---

## Plan vs Run: The Key Distinction

```
nimo> /plan "write a haiku about AI"
▶ produce plan
  let haiku = structured Haiku "write a haiku about AI"
  save "haiku.md", haiku
  say "done"
  
  # Plan produced. Not executed.
  # User can review, edit, then run.
nimo> /run "let haiku = structured Haiku \"write a haiku about AI\"; save \"haiku.md\", haiku; say \"done\""
▶ generate
  wrote 47 bytes -> haiku.md
▶ done
nimo> 
```

**Separation of concerns:**
- `/plan` = **compile** (like `nim check`)
- `/run` = **execute** (like `nim run`)

This lets you:
1. See what the agent would do
2. Edit the plan if needed
3. Execute with confidence

---

## How It Feels

```
nimo> /plan "write a story about a lighthouse"
▶ produce plan
  let premise = "a lighthouse keeper discovers a message in a bottle"
  let outline = structured StoryOutline "create a story outline for: " & premise
  save "outline.json", outline
  
  for char in outline.characters:
      let wiki = structured CharacterWiki "write wiki entry for: " & char
      save "wikis/" & char & ".json", wiki
  ...
  
  # Plan has 12 steps. 3 loops. Ready to run.
nimo> /run   # or just press Enter to accept
▶ generate
  wrote 412 bytes -> outline.json
▶ loop: characters (4 items)
  ...
▶ story complete
nimo> 
```

