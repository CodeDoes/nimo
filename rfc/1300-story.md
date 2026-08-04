# 1300 — Story

The creative writing workflow. **Status: implemented** in `src/story.nim`
(pipeline logic) + `src/workspace.nim` (storage).

## What it is

Story mode is a longer, quality-checked writing flow: premise → outline →
chapters → validation → critique → saved to a workspace, with character memory
for consistency.

## The flow

```
premise
  └─> generateOutline() → outline.md
        └─> per chapter:
              generateChapter(wiki context + recap)
              validateChapter() — words / paragraphs / repeats
              fail → critiqueChapter() → one revision → re-validate
              save → chapters/0N_....md
```

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
