## What is this file for?

Current state of the project — what works, what's leftover.

## All Fixed

The issues documented here were resolved in commit `7358a63`:
- Core modules restored (`rwkv.nim`, `tokenizer.nim`, `sampling.nim`, `macros.nim`, `config.nim`, `logger.nim`)
- Syntax errors fixed (`cli.nim` export syntax, `nimwave_app.nim` Key.Q, unicode import)
- Unused imports cleaned up
- All 14 source files compile clean

## Remaining (Non-Blocking)

1. **`rwkv.cpp/` submodule** — still excluded from git. Must build `librwkv.so` manually before linking. This is by design.
2. **No subdirectory structure** — all 14 files are flat in `src/`. See `analysis/refactor-plan.md` for the proposed reorganization.
3. **DRY gaps** — chat turn generation logic is duplicated between `chat.nim` and `nimwave_app.nim`. See `analysis/dry.md`.

## Next Steps

See `analysis/refactor-plan.md` for the phased plan to:
1. Extract `session.nim` to eliminate duplicated init and chat logic
2. Reorganize into `engine/`, `ui/`, `apps/`, `tests/` subdirectories
3. Clean up nimble manifest
