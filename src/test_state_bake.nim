## test_state_bake.nim — deterministic verification that state_bake is sound.
##
## Core correctness property: resuming from a baked/checkpointed state must be
## EXACTLY equivalent to continuing the same sequence from scratch. The model
## here is tiny + deterministic (CPU float32), so the assertion is bitwise.
##
##   path A (continue):    eval(whole context incl. tail)            -> logitsA
##   path B (checkpoint):  eval(context up to cut) -> save state
##                         -> NEW state -> load cached -> eval(tail) -> logitsB
##   assert logitsA == logitsB
##
## Then assert the cache round-trips (save/load) byte-for-byte and that keying
## is stable. This is exactly what state_bake relies on: a saved state is a
## faithful checkpoint of the conversation, not an approximation.
##
## NOTE: the tiny model has only 256 vocab ids, so we feed raw token arrays
## (like rwkv.cpp's own tiny tests) rather than tokenizing text — the real
## bakeContext -> tokenizer path is exercised by the online smoke/evals.
##
## Build (devenv): nim c -o:build/test_state_bake src/test_state_bake.nim
## Run:            LD_LIBRARY_PATH=... ./build/test_state_bake

import std/[os, strformat, strutils, math, random, sequtils]
import ./rwkv, ./macros, ./state_cache

const
  TinyModel* = "rwkv.cpp/tests/tiny-rwkv-4v0-660K-FP32.bin"
  VocabPath* = "rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt"

var passCount = 0
var failCount = 0

proc step(name: string, body: proc()) =
  try:
    body()
    inc passCount
    echo "  [PASS] " & name
  except CatchableError as e:
    inc failCount
    echo "  [FAIL] " & name
    echo "         " & e.msg

proc assertFloatsEqual(a, b: openArray[float32], label: string) =
  if a.len != b.len:
    raise newException(ValueError, label & ": length mismatch " & $a.len & " vs " & $b.len)
  var maxDiff = 0.0'f32
  var i = 0
  for (x, y) in zip(a, b):
    let d = abs(x - y)
    if d > maxDiff: maxDiff = d
    inc i
  if maxDiff != 0.0'f32:
    raise newException(ValueError, label & ": max abs diff " & $maxDiff)

proc runStateBakeTest() =
  echo "======================================================"
  echo "state_bake equivalence test (deterministic, tiny model)"
  echo "======================================================"
  doAssert fileExists(TinyModel), "tiny test model missing: " & TinyModel

  var model: RwkvModel
  step("load tiny deterministic model"):
    model = initRwkvModel(TinyModel, nThreads = 2, nGpuLayers = 0)

  # A deterministic token sequence (ids < 256 so the tiny model evals them).
  let context: seq[uint32] = @[5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60]
  let savePoint = 6                    # checkpoint after this many tokens
  let tail = context[savePoint .. ^1]

  let cache = initStateCache(getTempDir() / "nimo_statebake_test")
  removeDir(cache.cacheDir)
  createDir(cache.cacheDir)

  var logitsContinue: seq[float32]
  var logitsResume: seq[float32]

  step("checkpoint == continue (bitwise logits)"):
    # path A: evaluate all tokens in one shot
    var sA = model.newState()
    var lA = model.newLogits()
    doAssert model.evalSequenceInChunks(context, 4, sA, lA)
    logitsContinue = lA

    # path B: eval prefix, save state, then in a NEW state load + continue
    var prefixState = model.newState()
    var lB = model.newLogits()
    doAssert model.evalSequenceInChunks(context[0 ..< savePoint], 4, prefixState, lB)
    let cachePath = statePath(cache, stateCacheKey(TinyModel, VocabPath, "ctx"))
    saveStateToFile(prefixState, cachePath)
    var resumed = model.newState()
    doAssert loadStateFromFile(resumed, cachePath)
    doAssert model.evalSequenceInChunks(tail, 4, resumed, lB)
    logitsResume = lB

    assertFloatsEqual(logitsContinue, logitsResume, "continue-vs-checkpoint logits")

  step("cache file exists & size matches state"):
    let sp = statePath(cache, stateCacheKey(TinyModel, VocabPath, "ctx"))
    doAssert fileExists(sp), "no cache file: " & sp
    doAssert getFileSize(sp) == model.stateLen * sizeof(float32)

  step("save/load round-trips state byte-for-byte"):
    var orig = model.newState()
    var ol = model.newLogits()
    discard model.evalSequenceInChunks(context, 4, orig, ol)
    let p = statePath(cache, stateCacheKey(TinyModel, VocabPath, "roundtrip"))
    saveStateToFile(orig, p)
    var loaded = model.newState()
    doAssert loadStateFromFile(loaded, p)
    assertFloatsEqual(orig, loaded, "roundtrip")

  echo "------------------------------------------------------"
  echo "  $1 passed, $2 failed" % [$passCount, $failCount]
  quit(if failCount == 0: 0 else: 1)

when isMainModule:
  runStateBakeTest()