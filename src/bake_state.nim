## RWKV State Baker Script
## Evaluates a pre-prompt / system prompt into model state and bakes (saves) the binary state file.

import std/[os, strutils, strformat, times]
import ./rwkv, ./config, ./tokenizer, ./logger, ./macros

proc main() =
  let modelPath = resolveModelPath(if paramCount() > 0: paramStr(1) else: DefaultModelPath)
  let promptArg = if paramCount() > 1: paramStr(2) else: DefaultPrompt
  let outStatePath = if paramCount() > 2: paramStr(3) else: "baked_state.bin"
  let vocabPath = if paramCount() > 3: paramStr(4) else: DefaultVocabPath

  let promptText = if fileExists(promptArg): readFile(promptArg) else: promptArg

  logSessionStart("RWKV State Baker", modelPath, vocabPath)

  echo "=========================================================="
  echo "         RWKV State Baking Tool                           "
  echo "=========================================================="
  echo "Model path:    ", modelPath
  echo "Vocab path:    ", vocabPath
  echo "Output state:  ", outStatePath
  echo "Prompt length: ", promptText.len, " chars"
  echo "----------------------------------------------------------"

  if not fileExists(modelPath):
    echo "Error: Model file not found at '", modelPath, "'"
    appendToEternalLog("Error: Model file not found at '" & modelPath & "'")
    return

  let tok = loadWorldTokenizer(vocabPath)
  echo "Vocab loaded successfully!"

  withModel(modelPath, DefaultThreads, DefaultGpuLayers, model):
    echo &"Model loaded! (nVocab={model.nVocab}, nLayer={model.nLayer}, stateLen={model.stateLen})"

    var promptTokens = tok.encode(promptText)
    if promptTokens.len == 0:
      echo "Error: Prompt token sequence is empty."
      return

    echo &"Encoding prompt -> {promptTokens.len} tokens"

    var state = model.newState()
    var logits = model.newLogits()
    var elapsed = 0.0

    timeBlock(elapsed):
      benchmarkStep("bake_state_eval"):
        checkOk(model.evalSequenceInChunks(promptTokens, chunkSize = DefaultChunkSize, state, logits),
                "Failed to evaluate state prompt sequence")

    echo "Saving baked state to binary file..."
    state.saveState(outStatePath)

    let fileSize = getFileSize(outStatePath)
    let msPerToken = elapsed / promptTokens.len.float * 1000.0

    echo "\n=========================================================="
    echo &" SUCCESS: Baked {promptTokens.len} tokens into '{outStatePath}'"
    echo &" State File Size: {fileSize} bytes ({fileSize.float / 1024.0:.2f} KB)"
    echo &" Evaluation Time: {elapsed:.3f} s ({msPerToken:.2f} ms/token)"
    echo "=========================================================="

    appendToEternalLog(&"Baked state file '{outStatePath}' ({promptTokens.len} tokens, {fileSize} bytes) in {elapsed:.3f} s")

when isMainModule:
  main()
