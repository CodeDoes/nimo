## What is this file for?

Concrete plan for simplifying `src/`.

## Phase 1: Extract Shared Logic (no structure change)

Create `src/session.nim` with:

```nim
## Session management for RWKV chat/generation.
## Encapsulates the common pattern: load model + tokenizer,
## generate a turn, clean up after the turn.

import std/[random, times]
import ./rwkv, ./config, ./tokenizer, ./sampling, ./macros, ./logger

type
  Session = object
    model: RwkvModel
    tok: WorldTokenizer
    state: seq[float32]
    logits: seq[float32]
    rng: Rand

proc initSession*(modelPath, vocabPath: string): Session =
  ## Load model and tokenizer. Raises on failure.
  result.tok = loadWorldTokenizer(vocabPath)
  result.model = initRwkvModel(modelPath, DefaultThreads, DefaultGpuLayers)
  result.state = result.model.newState()
  result.logits = result.model.newLogits()
  result.rng = initRand(cpuTime().int64)

proc generateTurn*(s: var Session, userMsg: string, maxTokens: int = 200): string =
  ## Encode user message, generate bot reply. Returns the reply text.
  ## Handles EOS, stop sequences, and end-of-turn cleanup.
  let turnPrompt = "User: " & userMsg & "\n\nBot:"
  let turnTokens = s.tok.encode(turnPrompt)
  checkOk(s.model.evalSequenceInChunks(turnTokens, DefaultChunkSize, s.state, s.logits),
          "Failed to evaluate prompt")

  var reply = ""
  var validState = s.state
  for step in 0 ..< maxTokens:
    streamToken(s.model, s.state, s.logits, s.tok, DefaultTemp, DefaultTopP, s.rng, token, tokenStr):
      if token == 0:
        s.state = validState
        break
      reply.add(tokenStr)
      if endsWithStopSequence(reply):
        s.state = validState
        break
      if not s.model.eval(token.uint32, s.state, s.logits):
        break
      validState = s.state

  # End-of-turn cleanup
  let endTokens = s.tok.encode("\n\n")
  if endTokens.len > 0:
    discard s.model.evalSequence(endTokens, s.state, s.logits)

  return reply.strip()
```

Then each binary becomes:

```nim
# chat.nim — ~60 lines instead of ~137
import cli, ./session

proc main() =
  let modelPath = resolveModelPath(paramStr(0))
  let vocabPath = DefaultVocabPath
  logSessionStart("Chat", modelPath, vocabPath)
  printBanner "Chat"

  var s = initSession(modelPath, vocabPath)
  while true:
    stdout.write("\nUser: "); stdout.flushFile()
    let input = readLine(stdin).strip()
    if input == "/quit" or input == "/exit": break
    if input == "/reset":
      s = initSession(modelPath, vocabPath); continue
    let reply = s.generateTurn(input)
    echo "Bot:  ", reply
    logChatInteraction(input, reply)
```

## Phase 2: Reorganize into Subdirectories

```
src/
├── engine/     config.nim, model.nim (was rwkv.nim), tokenizer.nim, sampler.nim (was sampling.nim), session.nim (new)
├── ui/         cli.nim, logger.nim, macros.nim
├── apps/       main.nim, generate.nim, chat.nim, bake_state.nim, dashboard.nim (was nimwave_app.nim)
└── tests/      test_model.nim, test_tokenizer.nim
```

Update `nico.nimble`:
```nim
srcDir = "src"
# Nim handles subdirectories automatically with module-relative imports
```

Update imports in all files:
- `import ./rwkv` → `import ../engine/model`
- `import ./config` → `import ../engine/config`
- etc.

## Phase 3: Clean Up

- Remove `test_rwkv_full.nim` and `test_tokenizer.nim` from nimble `bin` list (they're test programs, not shipped binaries)
- Consider making them `tests/` module instead of `src/tests/`
- Update `analysis/issues.md` to reflect current state
- Add `analysis/refactor.md` documenting this plan
