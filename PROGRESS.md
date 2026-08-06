# PROGRESS.md

## Current State
- **Baseline: `v0.7.0`** — solid working app
- **Multi-turn**: 5 turns verified (Alice remembered, math correct)
- **Tests**: 87/87 pass
- **Backend**: CUDA on RTX 2050

## Working
- [x] `./bin/nimo harness` — interactive agent (5+ turns)
- [x] `./bin/nimo generate` — single-shot generation
- [x] `./bin/nimo doctor` — health check
- [x] `./bin/nimo unit` — 87/87 tests
- [x] `./bin/nimo new "goal"` — create plan from goal
- [x] `./bin/nimo` PATH shim
- [x] State baking with examples

## Known Issues
- [ ] State cache can corrupt across runs (clear with `rm -rf .nimo/state-cache`)
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
- `v0.7.0` — current baseline (revert: `git checkout v0.7.0`)
