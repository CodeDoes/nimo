# PROGRESS.md

## Current State
- **Baseline: `v0.3.0`** — solid working app
- **Multi-turn**: 3+ turns verified (Alice remembered, no loops)
- **Tests**: 87/87 pass
- **Backend**: CUDA on RTX 2050

## Working
- [x] `./bin/nimo harness` — interactive agent (3+ turns)
- [x] `./bin/nimo generate` — single-shot generation
- [x] `./bin/nimo doctor` — health check
- [x] `./bin/nimo unit` — 87/87 tests
- [x] `./bin/nimo` PATH shim
- [x] State baking with examples

## Known Issues
- [ ] State cache can corrupt across runs (clear with `rm -rf .nimo/state-cache`)
- [ ] `chat` command has output formatting bugs
- [ ] `generate` slow after first run (GPU cache issue)
- [ ] CLI `--` separator broken in `nimble run`

## Commands
```bash
./bin/nimo harness      # interactive agent
./bin/nimo generate --prompt "Hello"
./bin/nimo doctor
./bin/nimo unit
```

## Git Tags
- `v0.3.0` — current baseline (revert with `git checkout v0.3.0`)
