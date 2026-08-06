# NOTES.md

## Follow-ups for Kit

### Immediate
1. **Fixed: Multi-turn conversation loop** — Root cause was two-fold:
   - State wasn't being baked (nimo.json had no systemPrompt/bakeContext)
   - No stop sequence for token-0 during generation
   - **Fix**: Added conversation examples to systemPrompt in nimo.json, added `\x00` stop check in generation loop
   - **Verified**: 5-turn conversation works, model remembers Alice, no loops

2. **CLI `--` separator** — `nimble run nimo -- cmd` is broken. Options:
   - Fix the CLI parser to handle `--`
   - Document workaround: `nimble run nimo cmd --flags`
   - Add alias/shim that handles it

### Medium-term
3. **README Quick Start** — Add `nimo harness` and `nimble run nimo` to the visible quick start section. Currently buried.

4. **Compiler warnings** — 11 warnings on every build:
   - Deprecated `sha1` imports → install `checksums` package
   - Unused imports in `nimo.nim` → clean up
   - Implicit default values → add explicit semicolons

5. **Model file ambiguity** — Three Q4_K files, no guidance. Pick one as canonical, rename others, or add README note.

### UX Observations
- First interaction failing (nimo not in PATH) is a **High** severity issue — users will bounce
- `doctor` command is excellent — highlight it more
- Harness output is good but CUDA init logs are noisy — consider `--quiet` flag

### Questions for Kit
- Should token-0 be configurable? (some models may not use it)
- Is the repetition loop on turn 3+ a known RWKV-7 issue or a harness bug?
- Should we auto-add `./build` to PATH in `devenv shell`?

---

## Session Log

| Date | Topic | Key Finding |
|------|-------|-------------|
| 2026-08-06 | UX simulation | token-0 missing before User: was causing state not to reset between turns |
| 2026-08-06 | token-0 fix | Applied, verified turns 1-2 work, turn 3+ repeats |

_Last updated: 2026-08-06_
