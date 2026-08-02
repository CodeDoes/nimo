## What is this file for?

Architecture overview of the NIMO codebase.

## Project Structure

```
nimo/
├── nico.nimble      # Build manifest — 6 binaries, requires illwave + nimwave
├── src/
│   ├── cli.nim      # Shared CLI helpers (banners, colored output, time fmt)
│   ├── main.nim     # Binding smoke test — loads model, verifies eval works
│   ├── generate.nim # Text generation CLI — prompt → streamed output
│   ├── chat.nim     # Interactive chat CLI — line-by-line with /reset, /quit
│   ├── bake_state.nim # State serialization — bake prompt → binary state file
│   ├── nimwave_app.nim # Full TUI dashboard — illwave terminal buffer, dual-panel
├── docs/            # End-user documentation
├── rfc/             # Feature proposals and format specs
├── plan/            # Future work roadmap
└── logs/            # Eternal log output (runtime)
```

## Architecture Layers

1. **RWKV C++ Backend** — `rwkv.cpp` ( submodule not on disk). Provides `librwkv.so` with C API for model loading, state management, token evaluation.
2. **Nim FFI Bindings** — Was in `src/rwkv.nim`. Wraps C dynlib calls into `RwkvModel` ref object with `initRwkvModel`, `eval`, `evalSequenceInChunks`, `newState`, `newLogits`, etc.
3. **Tokenizer** — Was in `src/tokenizer.nim`. Implements `WorldTokenizer` with a byte-level trie for encode/decode.
4. **Sampling** — Was in `src/sampling.nim`. Temperature + Top-P nucleus sampling over logits.
5. **Macros/Helpers** — Was in `src/macros.nim`. Nim templates (`withModel`, `streamToken`, `timeBlock`, `checkOk`) and macros (`benchmarkStep`, `testStep`).
6. **Config/Logging** — Was in `src/config.nim` and `src/logger.nim`. Constants (default model path, threads, temp) and eternal log writes.
7. **CLI/Dashboard** — Current `src/` modules. Each binary imports `cli` + the deleted modules above.

## Execution Flow

All four run modes share the same pipeline:

```
load model (.bin GGML) → load tokenizer (vocab txt) → encode prompt → eval chunks into state
                                                                    ↓
                                              generate tokens (sample → eval loop)
                                                                    ↓
                                              decode tokens → stream output
```

- `main` — verify pipeline works end-to-end
- `generate` — prompt → N tokens, streamed to stdout
- `chat` — interactive loop with history, state preservation between turns
- `bake_state` — prompt → state.bin (for later loading without re-evaluating)
- `nimwave_app` — same as chat but with full-screen TUI dashboard (conversation + telemetry panels)
