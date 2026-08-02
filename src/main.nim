import std/[os, strformat]
import ./rwkv

proc main() =
  echo "=== RWKV Nim Binding Test ==="
  echo "System info: ", getSystemInfo()

  let modelPath = if paramCount() > 0: paramStr(1) else: "model.bin"

  if not fileExists(modelPath):
    echo &"Model file '{modelPath}' not found. Nim bindings compiled successfully!"
    return

  echo &"Loading model from {modelPath}..."
  let model = initRwkvModel(modelPath, nThreads = 4, nGpuLayers = 0)
  echo &"Vocab size: {model.nVocab}"
  echo &"Embed size: {model.nEmbed}"
  echo &"Layer count: {model.nLayer}"
  echo &"State length: {model.stateLen}"
  echo &"Logits length: {model.logitsLen}"

  var state = model.newState()
  var logits = model.newLogits()

  # Evaluate first token (e.g. token 0)
  if model.eval(0.uint32, state, logits):
    echo "First token evaluation succeeded!"
  else:
    echo "Evaluation failed. Last error code: ", model.getLastError()

main()
