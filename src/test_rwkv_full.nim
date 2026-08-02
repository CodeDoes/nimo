import std/[os, strformat, math]
import ./rwkv

proc runFullTestSuite() =
  echo "========== RWKV Nim Binding Full Integration Test =========="

  # 1. System Info Test
  let sysInfo = getSystemInfo()
  echo "System info: ", sysInfo
  doAssert sysInfo.len > 0, "System info should not be empty"

  # 2. Test Model Loading
  let modelPath = "rwkv.cpp/tests/tiny-rwkv-4v0-660K-FP32.bin"
  doAssert fileExists(modelPath), "Test model file missing!"

  echo &"Loading model '{modelPath}'..."
  let model = initRwkvModel(modelPath, nThreads = 2, nGpuLayers = 0)
  doAssert model != nil and model.ctx != nil

  # 3. Model Parameters Inspection
  let nVocab = model.nVocab
  let nEmbed = model.nEmbed
  let nLayer = model.nLayer
  let stateLen = model.stateLen
  let logitsLen = model.logitsLen

  echo &"Model parameters:"
  echo &"  nVocab:    {nVocab}"
  echo &"  nEmbed:    {nEmbed}"
  echo &"  nLayer:    {nLayer}"
  echo &"  stateLen:  {stateLen}"
  echo &"  logitsLen: {logitsLen}"

  doAssert nVocab > 0, "nVocab must be positive"
  doAssert nEmbed > 0, "nEmbed must be positive"
  doAssert nLayer > 0, "nLayer must be positive"
  doAssert stateLen > 0, "stateLen must be positive"
  doAssert logitsLen == nVocab, "logitsLen should equal nVocab"

  # 4. State & Logits Allocation
  var state = model.newState()
  var logits = model.newLogits()
  doAssert state.len == stateLen
  doAssert logits.len == logitsLen

  # Check state initialization (non-NaN, initialized by rwkv_init_state)
  for v in state:
    doAssert not v.isNaN, "Initialized state should not contain NaNs"

  # 5. Single Token Evaluation (token = 100 < nVocab)
  echo "Testing single token eval (token = 100)..."
  let evalSuccess = model.eval(100.uint32, state, logits)
  doAssert evalSuccess, "eval failed"

  # Check that logits contain valid floats (not NaNs)
  var nonZeroLogits = 0
  for val in logits:
    doAssert not val.isNaN, "Logit value is NaN!"
    if val != 0.0:
      inc nonZeroLogits
  echo &"  Eval successful! Non-zero logits produced: {nonZeroLogits}/{logitsLen}"
  doAssert nonZeroLogits > 0

  # 6. Sequence Evaluation (tokens < nVocab)
  echo "Testing sequence eval ([10, 50, 100, 200])..."
  let tokens: seq[uint32] = @[10.uint32, 50, 100, 200]
  let seqSuccess = model.evalSequence(tokens, state, logits)
  doAssert seqSuccess, "evalSequence failed"
  echo "  Sequence eval successful!"

  # 7. Sequence Evaluation in Chunks
  echo "Testing sequence eval in chunks (chunkSize = 2)..."
  let chunkSuccess = model.evalSequenceInChunks(tokens, chunkSize = 2, state, logits)
  doAssert chunkSuccess, "evalSequenceInChunks failed"
  echo "  Chunked sequence eval successful!"

  # 8. Context Cloning
  echo "Testing model context cloning..."
  let clonedModel = model.clone(nThreads = 2)
  doAssert clonedModel != nil and clonedModel.ctx != nil
  doAssert clonedModel.nVocab == model.nVocab

  var clonedState = clonedModel.newState()
  var clonedLogits = clonedModel.newLogits()
  let cloneEvalSuccess = clonedModel.eval(50.uint32, clonedState, clonedLogits)
  doAssert cloneEvalSuccess, "Cloned model eval failed"
  echo "  Cloned model eval successful!"

  # 9. Model Quantization
  echo "Testing model quantization (FP32 -> Q8_0)..."
  let quantOutPath = "test_quantized_q8.bin"
  if fileExists(quantOutPath): removeFile(quantOutPath)

  let quantSuccess = quantizeModelFile(modelPath, quantOutPath, "Q8_0")
  doAssert quantSuccess, "quantizeModelFile failed"
  doAssert fileExists(quantOutPath), "Quantized model file not generated"
  echo &"  Quantization successful! Output file size: {getFileSize(quantOutPath)} bytes"

  # Load quantized model to verify it works
  let quantModel = initRwkvModel(quantOutPath, nThreads = 2, nGpuLayers = 0)
  var qState = quantModel.newState()
  var qLogits = quantModel.newLogits()
  doAssert quantModel.eval(100.uint32, qState, qLogits)
  echo "  Quantized model loaded and evaluated successfully!"

  # Clean up test output file
  removeFile(quantOutPath)

  # Explicit close test
  quantModel.close()
  clonedModel.close()
  model.close()

  echo "============================================================"
  echo "   SUCCESS: ALL RWKV NIM WRAPPER TESTS PASSED PERFECTLY!   "
  echo "============================================================"

when isMainModule:
  runFullTestSuite()
