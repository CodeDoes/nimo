# PROGRESS.md

## Current State
- **Baseline: `v0.9.0`** — solid working app
- **Multi-turn**: 2+ turns verified (Alice remembered)
- **Tests**: 87/87 pass
- **Backend**: CUDA on RTX 2050
- **Model lock**: Prevents OOM from concurrent loads

## Dev Workflow
```bash
# Compile and run (auto-builds if needed)
nimble harness
nimble unit
nimble generate -- --prompt "Hello" --max-length 10

# Or use pre-compiled binaries
./bin/nimo harness
./bin/nimo generate --prompt "Hello"
```

## Working
- [x] `nimble harness` — interactive agent (auto-compiles)
- [x] `./bin/nimo harness` — same, via PATH shim
- [x] `./bin/nimo generate` — single-shot generation
- [x] `./bin/nimo doctor` — health check
- [x] `./bin/nimo unit` — 87/87 tests
- [x] `./bin/nimo new "goal"` — create plan from goal
- [x] Model load lock (prevents OOM)
- [x] State baking with examples

## Known Issues
- [ ] `nimo run` uses stub generator
- [ ] CLI `--` separator broken in `nimble run`
- [ ] State cache can corrupt if model changes

## Git Tags
- `v0.9.0` — current baseline (revert: `git checkout v0.9.0`)
