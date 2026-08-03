# Plan: Story Pipeline - PARTIAL ✓

## Implemented

- `src/story.nim` - Story pipeline with validation
- Chapter validation (word count, paragraph count, repeating segments)
- Critique generation
- Wiki entry generation
- Chapter generation with context
- Outline generation

## Commands (CLI stubs)

```bash
nimo story generate <premise> --workspace <name>
nimo story validate <chapter> --workspace <name>
nimo story critique <chapter> --workspace <name>
nimo story outline --workspace <name>
```

## Validation Functions

```nim
proc validateChapter*(content: string): ChapterValidation
proc critiqueChapter*(content: string, chapterNum: int): CritiqueResult
proc generateWikiEntry*(session, characterName, traits): string
proc generateChapter*(session, chapterNum, title, wikiContext, previousRecap): string
proc summarizeChapter*(session, content): string
proc generateOutline*(session, premise): string
proc runStoryPipeline*(ws, session, premise, maxChapters): bool
```

## Next Steps

1. Integrate with real model inference
2. Add FIAAS (vector embedding search) for memory
3. Add session branching support
4. Implement full pipeline with retry logic
