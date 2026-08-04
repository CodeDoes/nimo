# 3200 — Story Pipeline

Multi-chapter story generation with validation. **Status: partial — the flow in
`src/story.nim` is a hardcoded approximation of the target plan-template form;
it also buffers through `generateTurn` (no streaming) and lacks the
extract-characters → per-character-wiki stage.**

## What it is

Turns a premise into a validated multi-chapter story via a **plan template**
executed by the engine. Pointed tools (`extract`) keep each step on a **focused
slice** — the model never sees the whole outline + all wikis at once.

## Quality rules (`validateChapter`)

| Check | Rule |
|-------|------|
| Word count | ≥ 500 words |
| Paragraphs | ≥ 5 non-empty paragraphs |
| Repeating segments | no 3-word sequences repeated 3+ times (looping) |

If all pass → quality `sqPass`. Otherwise `sqFail` with a list of issues.

## Target plan template

```
compiled from "write a story about X":
po = generate(outlineState, premise)                  → outline.md
     report "outline ready"
     extract(outline, "the characters")               → characters[]
loop c in characters:
     events = extract(outline, for: c)                 # focused: only c's events
     generate(wikiState, from: events)                 → wiki/{c}.md
loop ch in outline.chapters:
     beat   = extract(outline, for: ch)                # focused: only ch's beat
     wslice = extract(wiki,    for: ch's cast)         # focused: only ch's cast
     chapter = generate(chapterState, from: beat + wslice)   # STREAMING
     validation = validate(chapter)
     fail → critique → one revision → re-validate → keep best
     write chapters/{ch}.md
     report "chapter {ch} done"
report "story finished"
```

## Current code vs target

| Piece | Today (`story.nim`) | Target |
|-------|---------------------|--------|
| Outline | `generateOutline` → outline.md | `Generate` outline step |
| Characters | not extracted | `Extract` characters → per-character wiki |
| Chapter context | wiki context + recap, one string | `Extract` outline slice + wiki slice per chapter |
| Loop | hardcoded `for ch in 1..N` | data-driven `Loop` over `outline.chapters` |
| Generation | `session.generateTurn` (buffers) | streaming through a sink |
| Critique | `critiqueChapter` + one revision | `Validate` + critique step |

## Supporting helpers (already correct)

- `generateWikiEntry` — character wiki page.
- `summarizeChapter` — recap for continuity.
- `validateChapter` / `critiqueChapter` / `countWords` / `countLines` — the
  gates and counters.

## See Also

- [3300-workspace.md](3300-workspace.md) — where chapters and wikis live
- [3500-plan-format.md](3500-plan-format.md) — the plan template vocabulary
- [1300-story.md](1300-story.md) — the story workflow overview