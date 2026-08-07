# PROGRESS.md

## Current State
- **Baseline: `v0.9.0`** — solid working app
- **Multi-turn**: 3+ turns verified (user remembered, haiku generated)
- **Tests**: 102/102 unit pass (was 103/103 — the offline-only `ensureQuantized` check was dropped)
- **L1 CLI (runtime stub)**: 19/19 pass
- **Backend**: CUDA on RTX 2050 (real) / runtime `[stub]` for no-GPU/CI
- **Dev workflow**: devenv shell nimo-* commands
- **UX**: clean startup — no ggml_cuda_init chatter; `nimble build`/`unit`/`doctor` green

## Done — runtime stub replaces compile-time flags
Directive complete: no `-d:harnessOffline` anywhere. Real-vs-stub is a **runtime**
decision; ONE binary everywhere.

- [x] **`bootstrap.nim`**: `BootstrapResult.stub: bool`; new `canRunRealModel(cfg)`
  (model file exists + a backend lib dlopens) and a dedicated `stubSession`;
  `bootstrapSession` picks real vs stub at runtime.
- [x] **Removed all `when defined(harnessOffline)` forks** from source
  (session_manager, state_cache, rwkv/state/cache, model_cache, rwkv/quant/cache,
  repl, quantize) — all unconditional; per-file `nim check` clean.
- [x] **`unit.nim`**: dropped the offline `ensureQuantized` check, removed the flag
  from fixture strings. → 102/102.
- [x] **`nico.nimble`**: `unit` task no longer passes `-d:harnessOffline`.
- [x] **`model_evals.nim`** unwrapped + dedented (both `when` guards), imports
  merged to one point, unused `times`/`sequtils` dropped. `nim check`/build clean;
  planner eval runs.
- [x] **Docs de-flagged**: AGENTS.md, rfc/3400, rfc/9400, `scripts/cli_test.sh`,
      `devenv.nix` `nimo-test` (no `-d:`), repl.nim header (fixed orphan line).
- [x] **FULL BUILD**: `build_all` 10/10 → exit 0; `model_evals` binary builds.
- [x] **Runtime-stub verify**: unit 102/102 + `cli_test.sh` 19/19.
- [x] **Runtime degradation verified**: harness pointed at a config with a missing
      model path prints `[stub] no usable backend+model here` and exits 0
      (simulates no-GPU / jules-CPU / CI) — no hard failure.

## Next
- [ ] Commit + keep `main` synced with `origin/main`.

> Tooling: this machine's `grep` floods stderr with `libpcre2 … no version
> information` noise — use `rg`/`awk` (added to AGENTS.md Conventions).

## Working
- [x] `devenv shell nimo-harness` — interactive agent (3+ turns)
- [x] `devenv shell nimo-generate` — single-shot generation
- [x] `devenv shell nimo-doctor` — health check
- [x] `devenv shell nimo-unit` — tests
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
- [x] State cache corruption self-heals (NaN guard re-bakes); capped at 512 MB (was: corrupt across runs, clear manually)
- [ ] `nimo run` uses stub generator
- [x] nimo dispatcher now preserves quoted args (was: shell-split `--prompt "Say OK."` into `Say`+`OK.`)
- [x] Unified Protocol REPL (RFC 2110): `nimo repl` = send/queue/steer, planner, ws, session, story chapter/wiki, cuda, state — same bootstrap + runHarnessTurn seam as chat
- [ ] Chat `run_pipeline` -> route through the shared protocol registry (RFC 2110 follow-up)
- [ ] CLI `--` separator broken in `nimble run` (nimble-side forwarding; separate from the dispatcher fix)

## Commands
```bash
cd ~/dev/nimo
devenv shell

# Dev workflow
devenv shell nimo-harness
devenv shell nimo-unit
devenv shell nimo-generate -- "Hello"

# Or pre-compiled
./bin/nimo harness
./bin/nimo unit
./bin/nimo generate --prompt "Hello"
```

## Git Tags
- `v0.9.0` — current baseline (revert: `git checkout v0.9.0`)