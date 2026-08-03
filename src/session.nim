## Session Management for RWKV Chat and Generation
## Encapsulates model loading, token generation, and turn cleanup.

import std/[random, times, strutils]
import ./rwkv, ./config, ./tokenizer, ./sampling, ./macros, ./logger

type
  Session* = object
    model*: RwkvModel
    tok*: WorldTokenizer
    state*: seq[float32]
    logits*: seq[float32]
    rng*: Rand

proc initSession*(modelPath, vocabPath: string; gpuLayers: int = DefaultGpuLayers): Session =
  ## Loads model and tokenizer. Raises on failure.
  result.tok = loadWorldTokenizer(vocabPath)
  result.model = initRwkvModel(modelPath, DefaultThreads, uint32(gpuLayers))
  result.state = result.model.newState()
  result.logits = result.model.newLogits()
  result.rng = initRand(cpuTime().int64)

proc generateTurn*(s: var Session, userMsg: string, temp: float32 = DefaultTemp, topP: float32 = DefaultTopP, maxTokens: int = 200): string =
  ## Encodes user message, generates bot reply. Returns reply text.
  ## Handles EOS, stop sequences, and end-of-turn cleanup.
  let turnPrompt = "User: " & userMsg & "\n\nBot:"
  let turnTokens = s.tok.encode(turnPrompt)
  checkOk(s.model.evalSequenceInChunks(turnTokens, DefaultChunkSize, s.state, s.logits),
          "Failed to evaluate prompt")

  var reply = ""
  var validState = s.state
  for step in 0 ..< maxTokens:
    let token = sampleLogits(s.logits, temperature = temp, topP = topP, rng = s.rng)
    if token == 0:
      s.state = validState
      break
    let tokenStr = s.tok.decodeToken(token.uint32)
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
