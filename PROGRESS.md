# PROGRESS.md

## Current State
- **Baseline: `v0.9.0`** — solid working app
- **Multi-turn**: 4 turns verified (Alice remembered, capital of France)
- **Tests**: 87/87 pass
- **Backend**: CUDA on RTX 2050
- **Performance**: ~330ms/token (generate), ~3s/turn (harness)
- **GPU memory**: Cleanly released between runs

## Working
- [x] `./bin/nimo harness` — interactive agent (4+ turns)
- [x] `./bin/nimo generate` — single-shot generation
- [x] `./bin/nimo doctor` — health check
- [x] `./bin/nimo unit` — 87/87 tests
- [x] `./bin/nimo new "goal"` — create plan from goal
- [x] `./bin/nimo` PATH shim
- [x] State baking with examples
- [x] GPU memory cleanup

## Known Issues
- [ ] OOM if multiple processes load model simultaneously
- [ ] `nimo run` uses stub generator
- [ ] CLI `--` separator broken in `nimble run`

## Commands
```bash
./bin/nimo harness      # interactive agent (primary)
./bin/nimo generate --prompt "Hello"
./bin/nimo doctor
./bin/nimo unit
./bin/nimo new "write a poem"
```

## Git Tags
- `v0.9.0` — current baseline (revert: `git checkout v0.9.0`)
