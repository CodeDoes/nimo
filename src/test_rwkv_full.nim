import std/[os, strformat, math]
import ./rwkv, ./macros

proc runFullTestSuite() =
  echo "========== RWKV Nim Binding Full Integration Test =========="

  # 1. System Info Test
  testStep("System info inquiry"):
    let sysInfo = getSystemInfo()
    echo "  System info: ", sysInfo
    doAssert sysInfo.len > 0, "System info should not be empty"

  let modelPath = "rwkv.cpp/tests/tiny-rwkv-4v0-660K-FP32.bin"
  doAssert fileExists(modelPath), "Test model file missing!"

  var model: RwkvModel
  testStep("Loading model '" & modelPath & "'"):
    model = initRwkvModel(modelPath, nThreads = 2, nGpuLayers = 0)
    doAssert model != nil and model.ctx != nil

  testStep("Inspecting model parameters"):
    let nVocab = model.nVocab
    let nEmbed = model.nEmbed
    let nLayer = model.nLayer
    let stateLen = model.stateLen
    let logitsLen = model.logitsLen

    echo &"  nVocab: {nVocab}, nEmbed: {nEmbed}, nLayer: {nLayer}, stateLen: {stateLen}, logitsLen: {logitsLen}"
    doAssert nVocab > 0 and nEmbed > 0 and nLayer > 0 and stateLen > 0 and logitsLen == nVocab

  var state: seq[float32]
  var logits: seq[float32]
  testStep("State & Logits Allocation"):
    state = model.newState()
    logits = model.newLogits()
    doAssert state.len == model.stateLen
    doAssert logits.len == model.logitsLen
    for v in state:
      doAssert not v.isNaN, "State contains NaN"

  testStep("Single Token Evaluation"):
    let evalSuccess = model.eval(100.uint32, state, logits)
    doAssert evalSuccess, "eval failed"
    var nonZeroLogits = 0
    for val in logits:
      doAssert not val.isNaN, "Logit value is NaN!"
      if val != 0.0: inc nonZeroLogits
    doAssert nonZeroLogits > 0

  testStep("Sequence Evaluation ([10, 50, 100, 200])"):
    let tokens: seq[uint32] = @[10.uint32, 50, 100, 200]
    doAssert model.evalSequence(tokens, state, logits), "evalSequence failed"

  testStep("Sequence Evaluation in Chunks"):
    let tokens: seq[uint32] = @[10.uint32, 50, 100, 200]
    doAssert model.evalSequenceInChunks(tokens, chunkSize = 2, state, logits), "evalSequenceInChunks failed"

  testStep("Model Context Cloning"):
    let clonedModel = model.clone(nThreads = 2)
    doAssert clonedModel != nil and clonedModel.ctx != nil
    var clonedState = clonedModel.newState()
    var clonedLogits = clonedModel.newLogits()
    doAssert clonedModel.eval(50.uint32, clonedState, clonedLogits), "Cloned model eval failed"
    clonedModel.close()

  let quantOutPath = "test_quantized_q8.bin"
  testStep("Model Quantization (FP32 -> Q8_0)"):
    if fileExists(quantOutPath): removeFile(quantOutPath)
    doAssert quantizeModelFile(modelPath, quantOutPath, "Q8_0"), "quantizeModelFile failed"
    doAssert fileExists(quantOutPath), "Quantized model file not generated"

  testStep("Quantized Model Loading & Verification"):
    let quantModel = initRwkvModel(quantOutPath, nThreads = 2, nGpuLayers = 0)
    var qState = quantModel.newState()
    var qLogits = quantModel.newLogits()
    doAssert quantModel.eval(100.uint32, qState, qLogits)
    quantModel.close()
    if fileExists(quantOutPath): removeFile(quantOutPath)

  model.close()

  echo "============================================================"
  echo "   SUCCESS: ALL RWKV NIM WRAPPER TESTS PASSED PERFECTLY!   "
  echo "============================================================"

when isMainModule:
  runFullTestSuite()
