## Nim wrapper for rwkv.cpp — CLI-frontend wrapper combining illwave + std/terminal output

import std/[os, strformat]
import cli, rwkv, config, tokenizer, logger

proc main() =
  echo "=== RWKV Nim Binding Test ==="
  echo "System info: ", getSystemInfo()

  let modelPath = if paramCount() > 0: paramStr(1) else: DefaultModelPath
  let vocabPath = if paramCount() > 1: paramStr(2) else: DefaultVocabPath

  logSessionStart("RWKV Main Test", modelPath, vocabPath)

  if not fileExists(modelPath):
    printError &"Model file '{modelPath}' not found. Nim bindings compiled successfully!"
    appendToEternalLog &"Model file '{modelPath}' not found."
    return

  printInfo &"Loading model from {modelPath}..."
  let model = initRwkvModel(modelPath, nThreads = uint32(DefaultThreads), nGpuLayers = 0)
  printSuccess &"Vocab size: {model.nVocab}"
  printInfo      &"Embed size: {model.nEmbed}"
  printInfo      &"Layer count: {model.nLayer}"
  printInfo      &"State length: {model.stateLen}"
  printInfo      &"Logits length: {model.logitsLen}"

  if fileExists(vocabPath):
    printInfo &"Loading tokenizer from {vocabPath}..."
    let tok = loadWorldTokenizer(vocabPath)
    let samplePrompt = "Hello World! RWKV v7 model test."
    let tokens = tok.encode(samplePrompt)
    printSuccess &"Encoded prompt '{samplePrompt}' -> {tokens.len} tokens"
    printSuccess &"Decoded prompt -> '{tok.decode(tokens)}'"

  var state = model.newState()
  var logits = model.newLogits()

  # Evaluate first token (token 0)
  if model.eval(0.uint32, state, logits):
    printSuccess "First token evaluation succeeded!"
    appendToEternalLog "First token evaluation succeeded."
  else:
    printError "Evaluation failed. Last error code: " & $model.getLastError()
    appendToEternalLog "Evaluation failed. Error code: " & $model.getLastError()

when isMainModule:
  main()
