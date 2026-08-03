# Plan: Story Pipeline

## Goal

Implement multi-chapter story generation with wiki context per RFC 3200.

## Pipeline Steps

1. **Wiki Generation** - Create character/world entries
2. **Context Extraction** - Extract relevant details
3. **Chapter Generation** - Sequential with recap
4. **Validation** - Quality checks
5. **Critique** - Feedback loop
6. **Outline** - Finalize story structure

## Commands

```bash
nimo story create "cyberpunk robot ninja" --workspace myproject
nimo story generate --chapter 1
nimo story validate --chapter 1
nimo story critique --chapter 1
nimo story outline
```

## Validation Criteria

- Word count >= 500 per chapter
- Paragraph count >= 5 per chapter
- No repeating segments (>3 consecutive repeated words)
- Character consistency
- Plot coherence

## Implementation

1. `src/story.nim` - Story pipeline module
2. `src/validate.nim` - Quality validation
3. `src/critique.nim` - Critique pipeline
4. Update `pipeline.nim` with story-specific steps
