## RWKV Text Generation — CLI with session management

import std/[os, strutils, strformat, times]
import cli, ./session, ./config, ./tokenizer, ./rwkv, ./sampling, ./logger, ./macros

proc main() =
  let modelPath = resolveModelPath(if paramCount() > 0: paramStr(1) else: DefaultModelPath)
  let promptText = if paramCount() > 1: paramStr(2) else: DefaultPrompt
  let vocabPath = if paramCount() > 2: paramStr(3) else: DefaultVocabPath
  let genLength = DefaultGenLength

  logSessionStart("RWKV Generate", modelPath, vocabPath)
  printBanner "RWKV Text Generation"
  printConfig(modelPath, vocabPath)
  echo "Prompt:  ", promptText
  echo "Length:  ", genLength, " tokens"
  echo SepThin

  if not fileExists(modelPath):
    printError &"Model not found: {modelPath}"
    return

  var s = initSession(modelPath, vocabPath)

  var promptTokens = s.tok.encode(promptText)
  if promptTokens.len == 0:
    printError "Empty prompt."
    return

  var elapsed = 0.0
  var fullGenerated = ""
  var stepCount = 0

  timeBlock(elapsed):
    benchmarkStep("prompt_eval"):
      checkOk(s.model.evalSequenceInChunks(promptTokens, DefaultChunkSize, s.state, s.logits),
              "Failed to evaluate prompt")

    stdout.write(promptText)
    stdout.flushFile()

    for step in 0 ..< genLength:
      let token = sampleLogits(s.logits, temperature = DefaultTemp, topP = DefaultTopP, rng = s.rng)
      if token == 0: break
      let tokenStr = s.tok.decodeToken(token.uint32)
      fullGenerated.add(tokenStr)
      inc stepCount
      stdout.write(tokenStr)
      stdout.flushFile()
      if not s.model.eval(token.uint32, s.state, s.logits): break

  echo ""
  echo SepThin
  printSuccess &"Generated {stepCount} tokens in {elapsed:.3f}s ({elapsed / max(stepCount, 1).float * 1000.0:.2f} ms/token)"
  logGenerationRun(promptText, fullGenerated, elapsed, stepCount)

when isMainModule:
  main()
