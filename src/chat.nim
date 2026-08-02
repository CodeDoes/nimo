import std/[os, strutils, strformat, math, random, times, algorithm, terminal]
import ./rwkv, ./config, ./tokenizer, ./logger, ./macros

proc softmax(logits: openArray[float32]): seq[float32] =
  result = newSeq[float32](logits.len)
  if logits.len == 0: return

  var maxVal = logits[0]
  for v in logits:
    if v > maxVal: maxVal = v

  var sumExp = 0.0f
  for i, v in logits:
    let e = exp(v - maxVal)
    result[i] = e
    sumExp += e

  if sumExp > 0.0f:
    for i in 0 ..< result.len:
      result[i] /= sumExp

type Pair = object
  prob: float32
  idx: int

proc sampleLogits(logits: openArray[float32], temperature: float32 = 0.7f, topP: float32 = 0.7f, rng: var Rand): int =
  if logits.len == 0: return 0

  if temperature <= 0.001f:
    var maxIdx = 0
    var maxVal = logits[0]
    for i, v in logits:
      if v > maxVal:
        maxVal = v
        maxIdx = i
    return maxIdx

  var probs = softmax(logits)

  if topP < 1.0f and topP > 0.0f:
    var pairs = newSeq[Pair](probs.len)
    for i in 0 ..< probs.len:
      pairs[i] = Pair(prob: probs[i], idx: i)

    pairs.sort(proc(a, b: Pair): int = cmp(b.prob, a.prob))

    var cumSum = 0.0f
    var cutoffIdx = pairs.len - 1
    for i, p in pairs:
      cumSum += p.prob
      if cumSum >= topP:
        cutoffIdx = i
        break

    var keptSum = 0.0f
    var keptProbs = newSeq[float32](probs.len)
    for i in 0 .. cutoffIdx:
      var p = pairs[i].prob
      if temperature != 1.0f:
        p = pow(p, 1.0f / temperature)
      keptProbs[pairs[i].idx] = p
      keptSum += p

    if keptSum > 0.0f:
      for i in 0 ..< probs.len:
        probs[i] = keptProbs[i] / keptSum

  elif temperature != 1.0f:
    var sumP = 0.0f
    for i in 0 ..< probs.len:
      probs[i] = pow(probs[i], 1.0f / temperature)
      sumP += probs[i]
    if sumP > 0.0f:
      for i in 0 ..< probs.len:
        probs[i] /= sumP

  let r = rng.rand(1.0f)
  var accum = 0.0f
  for i, p in probs:
    accum += p
    if r <= accum:
      return i

  return probs.len - 1

const StopSequences = [
  "\n\nUser:",
  "\nUser:",
  "\n\nUser",
  "\nUser",
  "\n\nHuman:",
  "\nHuman:",
  "<|endoftext|>"
]

proc endsWithStopSequence(s: string): bool =
  for stopSeq in StopSequences:
    if s.endsWith(stopSeq):
      return true
  return false

proc maxStopPrefixLen(s: string): int =
  ## Returns length of longest suffix of `s` that is a prefix of any stop sequence
  result = 0
  for stopSeq in StopSequences:
    for prefixLen in 1 .. stopSeq.len:
      let prefix = stopSeq[0 ..< prefixLen]
      if s.endsWith(prefix):
        if prefixLen > result:
          result = prefixLen

proc startTuiChat() =
  var modelPath = if paramCount() > 0: paramStr(1) else: DefaultModelPath
  let vocabPath = if paramCount() > 1: paramStr(2) else: DefaultVocabPath
  let temp = DefaultTemp
  let topP = DefaultTopP

  if modelPath.endsWith(".st") or modelPath.endsWith(".pth") or modelPath.endsWith(".safetensors"):
    let lastDot = modelPath.rfind('.')
    let binCandidate = modelPath[0 ..< lastDot] & ".bin"
    if fileExists(binCandidate):
      modelPath = binCandidate

  logSessionStart("RWKV TUI Chat Session (4-bit GGML)", modelPath, vocabPath)

  styledEcho(styleBright, fgCyan, "==========================================================")
  styledEcho(styleBright, fgCyan, "             RWKV Interactive TUI Chat                    ")
  styledEcho(styleBright, fgCyan, "==========================================================")
  echo "Model path: ", modelPath
  echo "Vocab path: ", vocabPath
  echo "Commands:   /reset (clear history), /quit (exit)"
  echo "----------------------------------------------------------\n"

  if not fileExists(modelPath):
    styledEcho(fgRed, "Error: Model file not found at '", modelPath, "'")
    appendToEternalLog("Error: Model file not found at '" & modelPath & "'")
    return

  let tok = loadWorldTokenizer(vocabPath)
  styledEcho(fgGreen, "Vocab loaded successfully!")

  # Use Nim template `withModel` for automatic lifetime management
  withModel(modelPath, DefaultThreads, model):
    styledEcho(fgGreen, &"Model loaded! (nVocab={model.nVocab}, nLayer={model.nLayer})")
    echo ""

    var state = model.newState()
    var logits = model.newLogits()
    var rng = initRand(cpuTime().int64)

    # Initial prompt / system setup
    let initialUserMsg = "hi"
    let initialBotMsg = "Hello! How can I help you today?"
    let sysPrompt = "User: " & initialUserMsg & "\n\nBot: " & initialBotMsg & "\n\n"
    var sysTokens = tok.encode(sysPrompt)

    if sysTokens.len > 0:
      checkOk(model.evalSequenceInChunks(sysTokens, chunkSize = DefaultChunkSize, state, logits),
              "Failed to evaluate system prompt")

    styledEcho(fgCyan, "User: ", initialUserMsg)
    styledEcho(fgGreen, "Bot:  ", initialBotMsg)

    while true:
      stdout.write("\nUser: ")
      stdout.flushFile()
      var inputLine: string
      try:
        inputLine = readLine(stdin)
      except IOError, EOFError:
        break

      inputLine = inputLine.strip()
      if inputLine.len == 0:
        continue

      if inputLine == "/quit" or inputLine == "/exit":
        styledEcho(fgYellow, "Goodbye!")
        appendToEternalLog("User quit chat session.")
        break
      elif inputLine == "/reset":
        state = model.newState()
        logits = model.newLogits()
        if sysTokens.len > 0:
          discard model.evalSequenceInChunks(sysTokens, chunkSize = DefaultChunkSize, state, logits)
        styledEcho(fgYellow, "Chat session reset.")
        styledEcho(fgCyan, "User: ", initialUserMsg)
        styledEcho(fgGreen, "Bot:  ", initialBotMsg)
        appendToEternalLog("Chat session reset by user.")
        continue

      let turnPrompt = "User: " & inputLine & "\n\nBot:"
      var turnTokens = tok.encode(turnPrompt)

      if turnTokens.len > 0:
        benchmarkStep("chat_turn_eval"):
          if not model.evalSequenceInChunks(turnTokens, chunkSize = DefaultChunkSize, state, logits):
            styledEcho(fgRed, "Error evaluating user prompt.")
            appendToEternalLog("Error evaluating prompt: " & inputLine)
            continue

      stdout.write("Bot:  ")
      stdout.flushFile()

      var botReply = ""
      var buffer = ""
      var validState = state

      for step in 0 ..< 200:
        let nextToken = sampleLogits(logits, temperature = temp, topP = topP, rng = rng)
        let tokenStr = tok.decodeToken(nextToken.uint32)

        botReply.add(tokenStr)
        buffer.add(tokenStr)

        if endsWithStopSequence(botReply):
          state = validState
          break

        if not model.eval(nextToken.uint32, state, logits):
          break

        let prefixLen = maxStopPrefixLen(buffer)
        let safeLen = buffer.len - prefixLen
        if safeLen > 0:
          stdout.write(buffer[0 ..< safeLen])
          stdout.flushFile()
          buffer = buffer[safeLen .. ^1]
          validState = state

      if buffer.len > 0 and not endsWithStopSequence(botReply):
        stdout.write(buffer)
        stdout.flushFile()

      echo ""
      logChatInteraction(inputLine, botReply.strip())

when isMainModule:
  startTuiChat()
