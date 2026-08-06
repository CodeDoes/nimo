# PROGRESS.md

## Current State
- **Baseline: `v0.9.0`** — solid working app
- **Multi-turn**: 3+ turns verified (Alice remembered, haiku generated)
- **Tests**: 87/87 pass
- **Backend**: CUDA on RTX 2050
- **Dev workflow**: devenv shell nimo-* commands

## Working
- [x] `devenv shell nimo-harness` — interactive agent (3+ turns)
- [x] `devenv shell nimo-generate` — single-shot generation
- [x] `devenv shell nimo-doctor` — health check
- [x] `devenv shell nimo-unit` — 87/87 tests
- [x] `devenv shell nimo-new "goal"` — create plan from goal
- [x] `devenv shell nimo-chat` — simple chat
- [x] `./bin/nimo` PATH shim (alternative)
- [x] Model load lock (prevents OOM)
- [x] State baking with examples

## Verified Complex Usage
```
> my name is Alice and I love programming
Nice to meet you, Alice! I also love programming.

> what is my name and what do I love?
Your name is Alice and you love programming.

> write a haiku about AI
AI brings new possibilities,
Innovation and creativity,
The future is bright.
```

## Known Issues
- [ ] State cache can corrupt across runs (clear with `rm -rf .nimo/state-cache`)
- [ ] `nimo run` uses stub generator
- [ ] CLI `--` separator broken in `nimble run`

## Commands
```bash
cd ~/dev/nimo
devenv shell

# Dev workflow
devenv shell nimo-harness
devenv shell nimo-unit
devenv shell nimo-generate -- --prompt "Hello"

# Or pre-compiled
./bin/nimo harness
./bin/nimo unit
./bin/nimo generate --prompt "Hello"
```

## Git Tags
- `v0.9.0` — current baseline (revert: `git checkout v0.9.0`)
