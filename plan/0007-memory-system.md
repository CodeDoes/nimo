# Plan: Memory System

## Goal

Implement persistent memory for character context and story state per RFC vision.

## Components

1. **Character Memory** - Baked state per character
2. **Story Memory** - Chapter recaps and continuity
3. **World Memory** - Wiki entries and lore
4. **FIAAS** - Vector embedding search (simulated for now)

## Commands

```bash
nimo memory bake --character max --state baked_max.state
nimo memory load --character max --state baked_max.state
nimo memory search "robot ninja combat"
nimo memory export --format json
```

## Implementation

1. `src/memory.nim` - Memory management
2. `src/fiaas.nim` - FIAAS (simulated vector search)
3. Extend state_cache.nim for character-specific caching
