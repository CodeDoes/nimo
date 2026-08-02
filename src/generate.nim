import std/[os, strutils, strformat, math, random, times, algorithm]
import ./rwkv, ./config, ./tokenizer, ./logger

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

proc sampleLogits(logits: openArray[float32], temperature: float32 = 0.8f, topP: float32 = 0.8f, rng: var Rand): int =
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

    # Sort descending by probability
    pairs.sort(proc(a, b: Pair): int = cmp(b.prob, a.prob))

    var cumSum = 0.0f
    var cutoffIdx = pairs.len - 1
    for i, p in pairs:
      cumSum += p.prob
      if cumSum >= topP:
        cutoffIdx = i
        break

    # Zero out elements past cutoff
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

  # Weighted random sampling
  let r = rng.rand(1.0f)
  var accum = 0.0f
  for i, p in probs:
    accum += p
    if r <= accum:
      return i

  return probs.len - 1

proc generateText() =
  var modelPath = if paramCount() > 0: paramStr(1) else: DefaultModelPath
  let promptText = if paramCount() > 1: paramStr(2) else: DefaultPrompt
  let vocabPath = if paramCount() > 2: paramStr(3) else: DefaultVocabPath
  let genLength = DefaultGenLength
  let temp = DefaultTemp
  let topP = DefaultTopP

  if modelPath.endsWith(".st") or modelPath.endsWith(".pth") or modelPath.endsWith(".safetensors"):
    let lastDot = modelPath.rfind('.')
    let binCandidate = modelPath[0 ..< lastDot] & ".bin"
    if fileExists(binCandidate):
      modelPath = binCandidate

  logSessionStart("RWKV Text Generation", modelPath, vocabPath)

  echo "=========================================================="
  echo "         RWKV Text Generation Demo in Nim                 "
  echo "=========================================================="
  echo "Model path: ", modelPath
  echo "Vocab path: ", vocabPath
  echo "Prompt:     \"", promptText, "\""
  echo "Temp:       ", temp, " | Top-P: ", topP

  if not fileExists(modelPath):
    echo "Error: Model file not found at '", modelPath, "'"
    appendToEternalLog("Error: Model file not found at '" & modelPath & "'")
    return

  let tok = loadWorldTokenizer(vocabPath)
  echo "Vocab loaded successfully!"

  let model = initRwkvModel(modelPath, nThreads = DefaultThreads)
  echo &"Model loaded successfully! (nVocab={model.nVocab}, nLayer={model.nLayer})"

  # Encode prompt string to tokens using RWKV v20230424 World Tokenizer
  var promptTokens = tok.encode(promptText)
  if promptTokens.len == 0:
    echo "Error: Empty prompt token sequence."
    return

  var state = model.newState()
  var logits = model.newLogits()

  let startTime = cpuTime()

  # Process prompt in chunks
  if not model.evalSequenceInChunks(promptTokens, chunkSize = DefaultChunkSize, state, logits):
    echo "Failed to evaluate prompt sequence!"
    appendToEternalLog("Error: Failed to evaluate prompt sequence!")
    return

  var rng = initRand(12345)

  echo "\nGenerated completion:\n"
  stdout.write(promptText)
  stdout.flushFile()

  var fullGenerated = ""
  var stepCount = 0

  for step in 0 ..< genLength:
    let nextToken = sampleLogits(logits, temperature = temp, topP = topP, rng = rng)
    let tokenStr = tok.decodeToken(nextToken.uint32)

    fullGenerated.add(tokenStr)
    inc stepCount

    stdout.write(tokenStr)
    stdout.flushFile()

    # Feed next token back into RWKV autoregressively
    if not model.eval(nextToken.uint32, state, logits):
      echo "\nError during evaluation step ", step
      break

  let elapsed = cpuTime() - startTime
  echo "\n\n----------------------------------------------------------"
  echo &"Generated {genLength} tokens in {elapsed:.3f} s ({elapsed / genLength.float * 1000.0:.2f} ms/token)"
  echo "=========================================================="

  logGenerationRun(promptText, fullGenerated, elapsed, stepCount)

when isMainModule:
  generateText()
