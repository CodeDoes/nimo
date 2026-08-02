import std/[macros, times, strutils, random]
import ./rwkv, ./logger, ./config, ./sampling

template withModel*(path: string, threads: int = DefaultThreads, gpuLayers: int = DefaultGpuLayers, modelVar, body: untyped): untyped =
  ## Nim Template: Safely instantiates an RWKV model and guarantees cleanup via defer.
  block:
    let modelVar = initRwkvModel(path, nThreads = threads.uint32, nGpuLayers = gpuLayers.uint32)
    defer:
      if modelVar != nil:
        modelVar.close()
    body

template timeBlock*(elapsedVar: var float, body: untyped): untyped =
  ## Nim Template: Measures CPU execution time of body block in seconds.
  block:
    let t0 = cpuTime()
    body
    elapsedVar = cpuTime() - t0

template checkOk*(callExpr: bool, errorMsg: string): untyped =
  ## Nim Template: Evaluates C API call, throwing descriptive RwkvException on failure.
  block:
    if not callExpr:
      let err = decodeError(rwkv_get_last_error(nil))
      raise newException(RwkvException, errorMsg & (if err.len > 0: " (" & err & ")" else: ""))

macro benchmarkStep*(name: static string, body: untyped): untyped =
  ## Nim Macro: Metaprogramming AST transformation to instrument and log performance metrics.
  let nameNode = newLit(name)
  quote do:
    let startT = cpuTime()
    `body`
    let duration = (cpuTime() - startT) * 1000.0
    appendToEternalLog("Benchmark [" & `nameNode` & "]: " & duration.formatFloat(ffDecimal, 2) & " ms")

macro testStep*(description: typed, body: untyped): untyped =
  ## Nim Macro: Metaprogramming AST wrapper for test steps with formatted execution timing.
  quote do:
    echo `description` & "..."
    let t0 = cpuTime()
    try:
      `body`
      let elapsedMs = (cpuTime() - t0) * 1000.0
      echo "  Step successful! (" & elapsedMs.formatFloat(ffDecimal, 2) & " ms)"
    except Exception as ex:
      echo "  Step failed: " & ex.msg
      raise ex

template streamToken*(model: RwkvModel, state, logits: openArray[float32], tok: auto, temp, topP: float32, rng: var Rand, tokenVar, tokenStrVar: untyped, body: untyped): untyped =
  ## Nim Template: Samples next token, decodes it, and executes body.
  let tokenVar = sampleLogits(logits, temperature = temp, topP = topP, rng = rng)
  let tokenStrVar = tok.decodeToken(tokenVar.uint32)
  `body`
