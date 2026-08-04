# Story Writing — How It Works

The story pipeline takes a premise and produces validated chapters. This page
walks through each step in plain language.

## The quality bar (what "good" means)

Every chapter is checked with classic, deterministic rules:

| Check | Rule |
|-------|------|
| Word count | at least 500 words |
| Paragraph count | at least 5 non-empty paragraphs |
| Repeating segments | no repeated 3-word sequences (looping text) |

These live in `src/story.nim` (`validateChapter`) and are pure logic — no model
involved — so they are fast and always consistent.

## Step by step

### 1. Generate an outline

Given a premise (e.g. "a cyberpunk detective who can't dream"), the model is
asked for a full outline: title, logline, main characters, world, plot summary
(beginning/middle/end), a 5–7 chapter breakdown, and themes.

The outline is saved to `outline.md` in the workspace.

### 2. Generate chapters one at a time

For each chapter (1 to N):

- The model gets the chapter number and title.
- Optionally it gets **wiki context** (character/world notes) and a **recap**
  of the previous chapter, so the story stays consistent.
- The prompt asks for 500+ words, 5+ paragraphs, dialogue, action, and a hook
  at the end.

### 3. Validate the chapter

The chapter text is checked with the table above:

- **PASS** → move on to the next chapter.
- **FAIL** → list the issues (e.g. "Word count too low: 320 < 500").

### 4. Critique + one revision attempt

When a chapter fails:

1. A critique is generated (`critiqueChapter`) with a score, weaknesses, and
   suggestions ("Fix: word count too low").
2. The model is asked to rewrite the chapter, explicitly told which checks it
   must satisfy.
3. The rewrite is validated again:
   - passes → keep the revision
   - still fails → keep the original (one attempt only, no infinite loop)

### 5. Save

Each chapter is written to the workspace as a numbered markdown file:
`chapters/01_my_title.md`, `chapters/02_...`, etc.

## Wiki pages

Characters and world notes live in `wiki/`. A wiki entry is created by giving
the model a name and traits; the prompt asks for a structured markdown entry
(physical description, personality, background, motivations, relationships,
abilities). The same validation philosophy applies: wiki content is generated
with the same quality expectations and can be checked/re-critiqued.

## Character memory

Character facts can be stored persistently (see [memory.md](memory.md)) so
later chapters can recall "what does this character want" without re-reading
the whole story. `rememberCharacter(name, description)` stores the fact, and
`getCharacterMemory(name)` retrieves it.

## Summaries for continuity

Between chapters the pipeline can produce a short summary of the previous
chapter (3–5 bullet points: key events, character development, revelations,
setup for the next chapter). That summary becomes the "previous recap" fed into
the next chapter generation, keeping the story on track.

## The whole flow at a glance

```
premise
  └─> outline (saved to outline.md)
        └─> for each chapter:
              ├─> generate chapter (wiki context + previous recap)
              ├─> validate (words / paragraphs / repeats)
              ├─> fail? -> critique -> one revision -> re-validate
              └─> save chapters/01_....md
        └─> optional: summarize chapter for continuity
```
