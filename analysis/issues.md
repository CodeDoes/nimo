## What is this file for?

Current blockers and issues preventing the project from building.

## Critical: Missing Core Modules

Every binary imports these deleted modules. None will compile:

```nim
import cli, rwkv, config, tokenizer, logger, sampling, macros
```

### Required Restorations

1. **`src/rwkv.nim`** — C FFI wrapper for `librwkv.so`. Contains `RwkvModel`, `initRwkvModel`, `eval`, `evalSequenceInChunks`, `newState`, `newLogits`, error types. ~260 lines.
2. **`src/tokenizer.nim`** — `WorldTokenizer` with trie-based encode/decode. ~181 lines.
3. **`src/sampling.nim`** — `softmax`, `sampleLogits` (temperature + topP). ~120 lines.
4. **`src/macros.nim`** — `withModel`, `streamToken`, `timeBlock`, `checkOk` templates + `benchmarkStep`, `testStep` macros. ~53 lines.
5. **`src/config.nim`** — `DefaultModelPath`, `DefaultTemp`, `DefaultTopP`, `resolveModelPath`. ~23 lines.
6. **`src/logger.nim`** — `appendToEternalLog`, `logSessionStart`, `logGenerationRun`, `logChatInteraction`. ~48 lines.

## Secondary: Missing Submodule

- **`rwkv.cpp/`** — excluded via `.gitignore`. The C++ shared library `librwkv.so` must be built manually via `nimble build_cpp`. Without it, no binary can link.

## Secondary: Build Manifest Mismatch

`nico.nimble` still references deleted binaries:
```nim
bin = @["main", "generate", "chat", "test_rwkv_full", "bake_state", "nimwave_app"]
```
`test_rwkv_full` no longer exists as a source file. Should be removed.

## Non-Breaking: Stale Imports in nimwave_app.nim

`nimwave_app.nim` imports `./rwkv, ./config, ./tokenizer, ./logger, ./sampling, ./macros` with `./` prefix (module-relative). All these paths are gone.
