# PROGRESS.md

## Current State
- **Baseline: `v0.1.0`** — solid working state
- **Multi-turn**: 6 turns verified (Alice remembered, math correct, haiku generated)
- **Tests**: 87/87 pass
- **Backend**: CUDA on RTX 2050

## Working
- [x] `./build/harness` — interactive agent (6+ turns)
- [x] `./build/generate` — single-shot text generation
- [x] `./build/nimo doctor` — health check
- [x] `./build/unit` — 87/87 tests
- [x] State baking with examples in nimo.json
- [x] Token-0 stop sequence prevents loops

## Known Issues
- [ ] `chat` command has output formatting bugs (shows "User: Bot:" prefix)
- [ ] `generate` is slow (~800ms/token) — may need GPU optimization
- [ ] `nimo` not in PATH — users must run `./build/nimo` or `nimble run nimo`
- [ ] CLI `--` separator broken in `nimble run`

## Next Priorities
1. Fix chat command output formatting
2. Add `bin/nimo` PATH shim
3. Fix CLI `--` separator
4. Optimize generate speed
5. Add README quick start with working examples

## Commands
```bash
# Harness (agent loop)
./build/harness

# Generate
./build/generate --backend cuda --prompt "Hello" --max-length 10

# Chat
./build/chat --backend cuda models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin

# Tests
./build/unit

# Health
./build/nimo doctor
```
