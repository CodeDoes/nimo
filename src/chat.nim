import std/[os, strutils, strformat, math, random, times, algorithm, terminal]
import ./rwkv, ./config

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

proc startTuiChat() =
  var modelPath = if paramCount() > 0: paramStr(1) else: DefaultModelPath
  let temp = DefaultTemp
  let topP = DefaultTopP

  if modelPath.endsWith(".st") or modelPath.endsWith(".pth") or modelPath.endsWith(".safetensors"):
    let lastDot = modelPath.rfind('.')
    let binCandidate = modelPath[0 ..< lastDot] & ".bin"
    if fileExists(binCandidate):
      modelPath = binCandidate

  styledEcho(styleBright, fgCyan, "==========================================================")
  styledEcho(styleBright, fgCyan, "             RWKV Interactive TUI Chat                    ")
  styledEcho(styleBright, fgCyan, "==========================================================")
  echo "Model path: ", modelPath
  echo "Commands:   /reset (clear history), /quit (exit)"
  echo "----------------------------------------------------------\n"

  if not fileExists(modelPath):
    styledEcho(fgRed, "Error: Model file not found at '", modelPath, "'")
    return

  let model = initRwkvModel(modelPath, nThreads = 4)
  styledEcho(fgGreen, &"Model loaded! (nVocab={model.nVocab}, nLayer={model.nLayer})")

  var state = model.newState()
  var logits = model.newLogits()
  var rng = initRand(cpuTime().int64)

  # Initial prompt / system setup
  let sysPrompt = "User: Hi!\n\nBot: Hello! How can I help you today?\n\n"
  var sysTokens = newSeq[uint32](sysPrompt.len)
  for i, c in sysPrompt:
    sysTokens[i] = uint32(ord(c)) mod model.nVocab.uint32

  discard model.evalSequenceInChunks(sysTokens, chunkSize = 16, state, logits)

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
      break
    elif inputLine == "/reset":
      state = model.newState()
      logits = model.newLogits()
      discard model.evalSequenceInChunks(sysTokens, chunkSize = 16, state, logits)
      styledEcho(fgYellow, "Chat session reset.")
      continue

    let turnPrompt = "User: " & inputLine & "\n\nBot:"
    var turnTokens = newSeq[uint32](turnPrompt.len)
    for i, c in turnPrompt:
      turnTokens[i] = uint32(ord(c)) mod model.nVocab.uint32

    if not model.evalSequenceInChunks(turnTokens, chunkSize = 16, state, logits):
      styledEcho(fgRed, "Error evaluating user prompt.")
      continue

    stdout.write("Bot: ")
    stdout.flushFile()

    var botReply = ""
    for step in 0 ..< 200:
      let nextToken = sampleLogits(logits, temperature = temp, topP = topP, rng = rng)
      let b = byte(nextToken mod 256)
      let ch = char(b)

      botReply.add(ch)

      if botReply.endsWith("\n\nUser:") or botReply.endsWith("\nUser:"):
        break

      if b >= 32.byte and b <= 126.byte:
        stdout.write(ch)
      elif b == 10.byte:
        stdout.write('\n')
      else:
        stdout.write('.')
      stdout.flushFile()

      if not model.eval(nextToken.uint32, state, logits):
        break

    echo ""

when isMainModule:
  startTuiChat()
