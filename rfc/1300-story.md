# 1300 — Story

The creative writing workflow. **Status: implemented** in `src/story.nim`
(pipeline logic) + `src/workspace.nim` (storage).

## What it is

Story mode is a longer, quality-checked writing flow. It runs as a **plan
template** executed by the engine (see [3500-plan-format.md](3500-plan-format.md)):
premise → outline → extract characters → per-character wiki → per-chapter
(extract focused outline+wiki slice → generate) → validation → critique → save.
Every generate step streams; memory keeps characters consistent.

## The flow (plan template)

```
premise
  └─> outline → outline.md
        └─> extract characters → per-character wiki (focused events)
              └─> per chapter:
                    extract outline slice + wiki slice for this chapter (focused)
                    generate chapter (500+ words) STREAMING
                    validateChapter() — words / paragraphs / repeats
                    fail → critiqueChapter() → one revision → re-validate
                    save → chapters/0N_....md
```

> Current status: `src/story.nim` implements a hardcoded approximation (no
> character-extraction stage, no streaming, no plan object). The target is the
> plan-template form in [3200-story.md](3200-story.md).

## What makes it different from chat

| Aspect | Chat | Story |
|--------|------|-------|
| Output length | short replies | 500+ word chapters |
| Consistency | conversation state | wiki context + previous recap |
| Quality control | none | validate → critique → revise |
| Storage | session JSONL | workspace `chapters/` + `wiki/` |
| Memory | none | character memory (see [memory docs](../docs/memory.md)) |

## Supporting pieces

- **Wiki entries** (`generateWikiEntry`) — structured character pages.
- **Summaries** (`summarizeChapter`) — 3–5 bullets per chapter for continuity.
- **Character memory** (`src/memory.nim`) — `rememberCharacter` /
  `getCharacterMemory` so facts persist.
- **Workspace** — chapters, wikis, outline, caches all live in the workspace
  folder (see [3300-workspace.md](3300-workspace.md)).

## See Also

- [3200-story.md](3200-story.md) — the story pipeline in detail (validation rules)
- [3300-workspace.md](3300-workspace.md) — where story files live
- [docs/story-writing.md](../docs/story-writing.md) — user-facing guide
