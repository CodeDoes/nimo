import std/[os, strformat]
import ./rwkv, ./config, ./tokenizer, ./logger

proc main() =
  echo "=== RWKV Nim Binding Test ==="
  echo "System info: ", getSystemInfo()

  let modelPath = if paramCount() > 0: paramStr(1) else: DefaultModelPath
  let vocabPath = if paramCount() > 1: paramStr(2) else: DefaultVocabPath

  logSessionStart("RWKV Main Test", modelPath, vocabPath)

  if not fileExists(modelPath):
    echo &"Model file '{modelPath}' not found. Nim bindings compiled successfully!"
    appendToEternalLog(&"Model file '{modelPath}' not found.")
    return

  echo &"Loading model from {modelPath}..."
  let model = initRwkvModel(modelPath, nThreads = DefaultThreads, nGpuLayers = 0)
  echo &"Vocab size: {model.nVocab}"
  echo &"Embed size: {model.nEmbed}"
  echo &"Layer count: {model.nLayer}"
  echo &"State length: {model.stateLen}"
  echo &"Logits length: {model.logitsLen}"

  if fileExists(vocabPath):
    echo &"Loading tokenizer from {vocabPath}..."
    let tok = loadWorldTokenizer(vocabPath)
    let samplePrompt = "Hello World! RWKV v7 model test."
    let tokens = tok.encode(samplePrompt)
    echo &"Encoded prompt '{samplePrompt}' -> {tokens.len} tokens"
    echo &"Decoded prompt -> '{tok.decode(tokens)}'"

  var state = model.newState()
  var logits = model.newLogits()

  # Evaluate first token (token 0)
  if model.eval(0.uint32, state, logits):
    echo "First token evaluation succeeded!"
    appendToEternalLog("First token evaluation succeeded.")
  else:
    echo "Evaluation failed. Last error code: ", model.getLastError()
    appendToEternalLog("Evaluation failed. Error code: " & $model.getLastError())

main()
