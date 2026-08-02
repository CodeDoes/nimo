## RWKV Text Generation — CLI with illwave / nimwave styled output

import std/[os, strutils, strformat, random, times]
import cli, rwkv, config, tokenizer, logger, sampling, macros

proc generateText() =
  let rawModelPath = if paramCount() > 0: paramStr(1) else: DefaultModelPath
  let modelPath = resolveModelPath(rawModelPath)
  let promptText = if paramCount() > 1: paramStr(2) else: DefaultPrompt
  let vocabPath = if paramCount() > 2: paramStr(3) else: DefaultVocabPath
  let genLength = DefaultGenLength
  let temp = DefaultTemp
  let topP = DefaultTopP

  logSessionStart("RWKV Text Generation (4-bit GGML)", modelPath, vocabPath)

  printBanner "RWKV Text Generation Demo in Nim"
  printConfig(modelPath, vocabPath)
  echo "Prompt:     \"", promptText, "\""
  echo "Temp:       ", temp, " | Top-P: ", topP
  echo SepThin

  if not fileExists(modelPath):
    printError &"Error: Model file not found at '{modelPath}'"
    appendToEternalLog &"Error: Model file not found at '{modelPath}'"
    return

  let tok = loadWorldTokenizer(vocabPath)
  printSuccess "Vocab loaded successfully!"

  withModel(modelPath, DefaultThreads, DefaultGpuLayers, model):
    printSuccess &"Model loaded successfully! (nVocab={model.nVocab}, nLayer={model.nLayer})"

    var promptTokens = tok.encode(promptText)
    if promptTokens.len == 0:
      printError "Error: Empty prompt token sequence."
      return

    var state = model.newState()
    var logits = model.newLogits()

    var elapsed = 0.0
    var fullGenerated = ""
    var stepCount = 0

    timeBlock(elapsed):
      benchmarkStep("prompt_chunk_eval"):
        checkOk(model.evalSequenceInChunks(promptTokens, chunkSize = DefaultChunkSize, state, logits),
                "Failed to evaluate prompt sequence")

      var rng = initRand(12345)

      echo ""
      printInfo "Generated completion:"
      stdout.write(promptText)
      stdout.flushFile()

      for step in 0 ..< genLength:
        streamToken(model, state, logits, tok, temp, topP, rng, nextToken, tokenStr):
          if nextToken == 0: # Token 0 = End of Text (EOS)
            break

          fullGenerated.add(tokenStr)
          inc stepCount

          stdout.write(tokenStr)
          stdout.flushFile()

          if not model.eval(nextToken.uint32, state, logits):
            printError &"Error during evaluation step {step}"
            break

    echo ""
    echo SepThin
    printSuccess &"Generated {stepCount} tokens in {elapsed:.3f} s ({elapsed / stepCount.float * 1000.0:.2f} ms/token)"
    echo BannerSep

    logGenerationRun(promptText, fullGenerated, elapsed, stepCount)

when isMainModule:
  generateText()
