# 3200 — Story Pipeline

Multi-chapter story generation with validation. **Status: implemented** in
`src/story.nim`.

## What it is

Turns a premise into a validated multi-chapter story, saved into a workspace.
Each chapter is checked against classic quality rules, and failing chapters go
through a critique + one revision attempt.

## Quality rules (`validateChapter`)

| Check | Rule |
|-------|------|
| Word count | ≥ 500 words |
| Paragraphs | ≥ 5 non-empty paragraphs |
| Repeating segments | no 3-word sequences repeated 3+ times (looping) |

If all pass → quality `sqPass`. Otherwise `sqFail` with a list of issues
("Word count too low: 320 < 500", ...).

## How it works (step by step)

### 1. Generate the outline

`generateOutline(premise)` asks the model for a full markdown outline: title,
logline, main characters, setting, plot summary, 5–7 chapter outline, themes.
Saved to `outline.md` in the workspace.

### 2. Generate chapters one by one

`runStoryPipeline(ws, session, premise, maxChapters)` loops 1..N:

- `generateChapter(num, title, wikiContext, previousRecap)` — the prompt asks
  for 500+ words, 5+ paragraphs, dialogue/action, and a hook. Wiki context and
  the previous chapter's recap keep things consistent.

### 3. Validate

The chapter text goes through `validateChapter`. If it passes, it's kept and
becomes the new recap.

### 4. Critique + revision on failure

If validation fails:

1. `critiqueChapter` produces a score (5.0 for fail), weaknesses (the issues),
   and suggestions ("Fix: ..."), and sets `shouldRevise = true`.
2. The model is asked to rewrite the chapter, explicitly told which checks it
   must satisfy.
3. The revision is validated again:
   - passes → keep the revision
   - fails → keep the original (one attempt only — no infinite loop)

### 5. Save

Each chapter is written via `ws.createChapter(num, title, content)` →
`chapters/01_<title>.md`, `02_...`, etc.

## Supporting helpers

- `generateWikiEntry(session, name, traits)` — character wiki page (structured
  markdown: description, personality, background, motivations, relationships,
  abilities).
- `summarizeChapter(session, content)` — 3–5 bullet points of key events,
  character developments, revelations, and setup for the next chapter (used as
  the next chapter's recap).
- `countWords` / `countLines` — the pure counters behind validation.

## The whole flow

```
premise
  └─> outline → outline.md
        └─> for ch in 1..N:
              generate chapter (wiki context + recap)
              validate -> pass? keep : (critique -> one revision -> keep best)
              save chapters/0N_....md
```

## See Also

- [3300-workspace.md](3300-workspace.md) — where chapters and wikis live
- [1300-story.md](1300-story.md) — the story workflow overview
- [1000-session.md](1000-session.md) — chapters are generated through sessions
