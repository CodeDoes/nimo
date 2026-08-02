import std/[macros, times, strutils]
import ./rwkv, ./logger

template withModel*(path: string, threads: int, modelVar, body: untyped): untyped =
  ## Nim Template: Safely instantiates an RWKV model and guarantees cleanup via defer.
  block:
    let modelVar = initRwkvModel(path, nThreads = threads.uint32)
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
