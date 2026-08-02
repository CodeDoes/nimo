## What is this file for?

What each source file does and why it exists.

## Library Modules (shared infrastructure)

These are imported by the binaries. They provide reusable capabilities.

### `rwkv.nim` (260 lines)
The C FFI bridge to `librwkv.so`. Wraps the RWKV inference engine.
- Loads GGML model files into a `RwkvModel` ref object
- Provides `eval`, `evalSequence`, `evalSequenceInChunks` via macro-generated overloads
- Manages state buffers (`newState`, `saveState`, `loadState`)
- Error decoding from C error flags
- **Why it's this big:** The macro-generated overloads alone are ~80 lines. The error decoding is ~40 lines. The rest is straightforward FFI.

### `tokenizer.nim` (181 lines)
WorldTokenizer: byte-level trie for RWKV's tokenization.
- `loadWorldTokenizer` — parses the vocab text file into a trie
- `encode` — greedy longest-match tokenization
- `decode` / `decodeToken` — reverse lookup
- **Why it's this big:** The vocab file parser handles escaped hex, unicode, and various quote styles. The trie encode is straightforward but needs the longest-match logic.

### `sampling.nim` (120 lines)
Token selection from logits.
- `softmax` — numerically stable softmax
- `sampleLogits` — temperature + Top-P nucleus sampling
- `StopSequences` — list of chat termination patterns
- `endsWithStopSequence` / `maxStopPrefixLen` — streaming stop detection
- **Why it's this big:** The Top-P cutoff + temperature rescaling logic is ~60 lines. The stop sequence helpers are ~20 lines.

### `config.nim` (23 lines)
Constants and path resolution.
- Model path, vocab path, prompt, generation params (temp, topP, chunk size, threads, GPU layers)
- `resolveModelPath` — auto-resolves `.st`/`.pth`/`.safetensors` to `.bin`
- **This is small and fine.**

### `macros.nim` (53 lines)
Nim templates and macros that reduce boilerplate.
- `withModel` — load model with automatic cleanup via `defer`
- `timeBlock` — measure elapsed time
- `checkOk` — throw on C API failure
- `benchmarkStep` — log timing to eternal log
- `streamToken` — sample + decode + run body (used in generation loops)
- **This is well-designed.** It's the main DRY mechanism.

### `logger.nim` (48 lines)
Append-only session logging.
- `logSessionStart`, `logGenerationRun`, `logChatInteraction`
- Writes to `logs/eternal.log`
- **Small and fine.**

### `cli.nim` (33 lines)
Colored stdout helpers.
- `printBanner`, `printError`, `printSuccess`, `printInfo`, `printWarn`
- Re-exports `styledEcho` from `std/terminal`
- **Small and fine.**

## Application Modules (binaries)

Each is a standalone executable. They all follow the same pattern:
1. Parse args / use defaults
2. Log session start
3. Print banner + config
4. Load tokenizer + model
5. Do work
6. Log results

### `main.nim` (48 lines)
Smoke test. Verifies the FFI works end-to-end. Loads model, encodes a prompt, evaluates one token.

### `generate.nim` (81 lines)
One-shot text generation. Prompt → N tokens streamed to stdout.
- Uses `streamToken` template for the generation loop
- Times the whole operation

### `chat.nim` (137 lines)
Interactive CLI chat. Line-by-line input, stateful conversation.
- Has its own token generation loop (duplicates logic from `nimwave_app.nim`)
- Handles `/reset` and `/quit` commands
- Supports baked state loading
- Streams output token-by-token with stop sequence handling

### `bake_state.nim` (65 lines)
Pre-compute and save model state from a prompt.
- Encodes prompt → eval → saves binary state file
- Useful for fast chat resume (skip re-evaluating the system prompt every time)

### `nimwave_app.nim` (267 lines)
Full-screen TUI dashboard. Dual-panel: conversation history + telemetry.
- Same chat turn logic as `chat.nim` but inlined (doesn't use `streamToken` template)
- Hand-draws box-drawing characters with illwave TerminalBuffer
- Runs an event loop polling keyboard input

## Test Modules

### `test_rwkv_full.nim` (98 lines)
Integration test for the RWKV FFI. Tests loading, eval, cloning, quantization, state save/load.

### `test_tokenizer.nim` (29 lines)
Round-trip test for the tokenizer: encode → decode should equal original string.
