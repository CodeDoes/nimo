## RWKV State Baker Script — CLI with nimwave/illwave styled output

import std/[os, strutils, strformat, times]
import cli, rwkv, config, tokenizer, logger, macros

proc main() =
  let modelPath = resolveModelPath(if paramCount() > 0: paramStr(1) else: DefaultModelPath)
  let promptArg = if paramCount() > 1: paramStr(2) else: DefaultPrompt
  let outStatePath = if paramCount() > 2: paramStr(3) else: "baked_state.bin"
  let vocabPath = if paramCount() > 3: paramStr(4) else: DefaultVocabPath

  let promptText = if fileExists(promptArg): readFile(promptArg) else: promptArg

  logSessionStart("RWKV State Baker", modelPath, vocabPath)

  printBanner "RWKV State Baking Tool"
  printConfig(modelPath, vocabPath)
  echo "Output state:  ", outStatePath
  echo "Prompt length: ", promptText.len, " chars"
  echo SepThin

  if not fileExists(modelPath):
    printError &"Error: Model file not found at '{modelPath}'"
    appendToEternalLog &"Error: Model file not found at '{modelPath}'"
    return

  let tok = loadWorldTokenizer(vocabPath)
  printSuccess "Vocab loaded successfully!"

  withModel(modelPath, DefaultThreads, DefaultGpuLayers, model):
    printSuccess &"Model loaded! (nVocab={model.nVocab}, nLayer={model.nLayer}, stateLen={model.stateLen})"

    var promptTokens = tok.encode(promptText)
    if promptTokens.len == 0:
      printError "Error: Prompt token sequence is empty."
      return

    printInfo &"Encoding prompt -> {promptTokens.len} tokens"

    var state = model.newState()
    var logits = model.newLogits()
    var elapsed = 0.0

    timeBlock(elapsed):
      benchmarkStep("bake_state_eval"):
        checkOk(model.evalSequenceInChunks(promptTokens, chunkSize = DefaultChunkSize, state, logits),
                "Failed to evaluate state prompt sequence")

    printInfo "Saving baked state to binary file..."
    state.saveState(outStatePath)

    let fileSize = getFileSize(outStatePath)
    let msPerTok = elapsed / promptTokens.len.float * 1000.0

    echo ""
    echo BannerSep
    printSuccess &"SUCCESS: Baked {promptTokens.len} tokens into '{outStatePath}'"
    printSuccess &"State File Size: {fileSize} bytes ({fileSize.float / 1024.0:.2f} KB)"
    printSuccess &"Evaluation Time: {elapsed:.3f} s ({msPerTok:.2f} ms/token)"
    echo BannerSep

    appendToEternalLog &"Baked state file '{outStatePath}' ({promptTokens.len} tokens, {fileSize} bytes) in {elapsed:.3f} s"

when isMainModule:
  main()
