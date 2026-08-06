# PROGRESS.md

## Current State
- **Baseline: `v0.2.0`** — solid working app
- **Multi-turn**: 6 turns verified (Alice, math, haiku)
- **Tests**: 87/87 pass
- **Backend**: CUDA on RTX 2050

## Working
- [x] `./bin/nimo harness` — interactive agent (6+ turns, no loops)
- [x] `./bin/nimo generate` — single-shot text generation
- [x] `./bin/nimo doctor` — health check
- [x] `./bin/nimo unit` — 87/87 tests
- [x] `./bin/nimo` PATH shim — works from repo root
- [x] State baking with conversation examples
- [x] Token-0 stop sequence prevents loops

## Known Issues
- [ ] `chat` command has display bugs (shows "User: Bot:" prefix)
- [ ] `generate` slow (~800ms/token after warmup)
- [ ] CLI `--` separator broken in `nimble run`
- [ ] GPU OOM if multiple processes load model simultaneously

## Next Improvements
1. Fix chat command output formatting
2. Add CUDA context cleanup between processes
3. Improve generate speed (warmup optimization)
4. Add `nimo new "goal"` one-liner for quick tasks
5. Add streaming progress indicator during generation

## Commands
```bash
# Interactive agent
./bin/nimo harness

# Single-shot generation
./bin/nimo generate --prompt "Hello"

# Health check
./bin/nimo doctor

# Tests
./bin/nimo unit
```

## Git Tags
- `v0.2.0` — solid baseline (revert with `git checkout v0.2.0`)
