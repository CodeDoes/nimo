# PROGRESS.md

## Current Focus
- **UX/DX simulation** — running user journey tests, capturing observations
- **Multi-turn conversation fix** — state baking with examples + token-0 stop sequence
- **Next**: Address High/Medium severity issues from critique/4.md

## Done
- [x] UX simulation step 1-3: PATH issue, `nimble run`, generate command
- [x] UX simulation step 4-6: chat, doctor, unit tests
- [x] UX simulation step 7: harness basic flow
- [x] **Fixed**: token-0 before `User:` in `generateTurnStream` (`session_manager.nim:101`) — but this alone didn't fix the loop
- [x] **Fixed**: state bake now includes conversation examples in `nimo.json` — this is what actually fixes the loop
- [x] **Fixed**: `\x00` stop sequence check in generation loop (`session_manager.nim:117`) — prevents infinite generation
- [x] Verified: 5-turn conversation works (Alice remembered, math correct, no loops)
- [x] 87/87 unit tests pass
- [x] Created `critique/4.md` with full UX observations
- [x] Created `MEGA_INSTRUCTIONS.md` with operating principles

## In Progress
- [ ] Fix repetition loop on turn 3+ (token-0 may be too aggressive)
- [ ] Run full UX simulation with step-by-step tmux
- [ ] Address High/Medium severity issues from critique

## Next
- [ ] Investigate turn 3+ repetition — is it token-0, context length, or state corruption?
- [ ] Add `PROGRESS.md` updates after each session
- [ ] Document `--` CLI separator fix or workaround

## Blockers
- None currently

## Notes
- token-0 (`\x00`) is essential for turn boundaries but may need tuning for longer conversations
- GPU is healthy (P8 idle, 3763 MiB free on RTX 2050)
- All builds use CUDA backend

_Last updated: 2026-08-06_
