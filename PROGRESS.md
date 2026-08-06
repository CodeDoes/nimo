# PROGRESS.md

## Current State
- **Baseline: `v0.4.0`** — solid working app
- **Multi-turn**: 3+ turns verified (Alice remembered, no loops)
- **Tests**: 87/87 pass
- **Backend**: CUDA on RTX 2050

## Working
- [x] `./bin/nimo harness` — interactive agent (3+ turns)
- [x] `./bin/nimo generate` — single-shot generation
- [x] `./bin/nimo doctor` — health check
- [x] `./bin/nimo unit` — 87/87 tests
- [x] `./bin/nimo new "goal"` — create plan from goal
- [x] `./bin/nimo run <plan>` — execute plan (stub for now)
- [x] `./bin/nimo` PATH shim

## Known Issues
- [ ] `chat` command has display bugs
- [ ] `nimo run` uses stub generator (needs model integration)
- [ ] State cache can corrupt across runs (clear with `rm -rf .nimo/state-cache`)
- [ ] CLI `--` separator broken in `nimble run`

## Commands
```bash
./bin/nimo harness      # interactive agent
./bin/nimo generate --prompt "Hello"
./bin/nimo doctor
./bin/nimo unit
./bin/nimo new "write a poem"
./bin/nimo run .nimo/programs/*.json
```

## Git Tags
- `v0.4.0` — current baseline (revert with `git checkout v0.4.0`)
