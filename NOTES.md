# NOTES.md

## Follow-ups for Kit

### Immediate
1. **Token-0 tuning** — The `\x00` fix works for turns 1-2 but causes repetition on turn 3+. Need to investigate:
   - Is token-0 too aggressive?
   - Should we use a softer reset (e.g., just `\n\n`)?
   - Is there a context length issue after multiple turns?

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
