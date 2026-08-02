## What is this file for?

Where repetition lives and how to eliminate it.

## Repetition #1: Common Initialization

Every binary does the same setup:

```nim
# ALL of these appear in main.nim, generate.nim, chat.nim, bake_state.nim, nimwave_app.nim:
let modelPath = resolveModelPath(if paramCount() > 0: paramStr(1) else: DefaultModelPath)
let vocabPath = if paramCount() > 1: paramStr(2) else: DefaultVocabPath
logSessionStart(...)
printBanner(...)
printConfig(...)
if not fileExists(modelPath): printError(...); return
let tok = loadWorldTokenizer(vocabPath)
withModel(modelPath, DefaultThreads, DefaultGpuLayers, model):
  ...
```

**Fix:** A `initSession` proc in a shared module that returns `(model, tok, state, logits)` or handles errors gracefully.

## Repetition #2: Chat Turn Generation

`chat.nim` and `nimwave_app.nim` both implement the same turn generation loop:

```
encode turn prompt → evalSequenceInChunks → sample tokens → eval each token → stop on EOS/stop-seq
```

`chat.nim` uses the `streamToken` template. `nimwave_app.nim` inlines the sampling (doesn't use the template at all).

**Fix:** Extract a `generateTurn(model, tok, state, logits, prompt, temp, topP, rng)` proc that returns `(reply: string, tokensGenerated: int, elapsed: float)`. Both binaries would call this.

## Repetition #3: System Prompt Setup

Both `chat.nim` and `nimwave_app.nim` hardcode the same system prompt:

```nim
let sysPrompt = "User: hi\n\nBot: Hello! How can I help you today?\n\n"
```

**Fix:** A constant in `config.nim`: `DefaultSystemPrompt`.

## Repetition #4: Model Loading

`nimwave_app.nim` calls `initRwkvModel` directly instead of using the `withModel` template that `chat.nim` and others use.

**Fix:** Use `withModel` consistently, or extract model loading into a helper.

## Repetition #5: End-of-Turn Cleanup

Both chat implementations do this at the end of every turn:

```nim
let endTurnTokens = tok.encode("\n\n")
if endTurnTokens.len > 0:
  discard model.evalSequence(endTurnTokens, state, logits)
```

**Fix:** A `finalizeTurn(model, tok, state, logits)` proc.

## Summary

| Repetition | Lines Duplicated | Easy to Fix? |
|------------|-----------------|-------------|
| Common init | ~30 lines × 5 files = 150 | Yes — `initSession` proc |
| Chat turn gen | ~40 lines × 2 files = 80 | Yes — `generateTurn` proc |
| System prompt | ~3 lines × 2 files = 6 | Yes — constant |
| Model loading pattern | ~5 lines × 2 files = 10 | Yes — use `withModel` consistently |
| End-of-turn cleanup | ~4 lines × 2 files = 8 | Yes — `finalizeTurn` proc |

Total potential reduction: ~254 lines of duplicated logic.
