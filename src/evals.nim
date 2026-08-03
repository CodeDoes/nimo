## NIMO Eval Harness
## Tests the harness loop deterministically with a scripted generator (no real model needed).
## Covers three dimensions from RFC 9300-eval:
##   1. Tool calling   - does the loop detect, dispatch, and feed back tool results?
##   2. Loop termination - does it stop on a final text answer / hit max-iteration guard?
##   3. Session logging - is the JSONL message tree (user -> tool_call -> tool_result -> text) well-formed?

import std/[strutils, os, times, json]
import ./session_manager, ./pipeline, ./harness, ./gpu, ./model_cache, ./state_cache

type
  Check* = object
    name*: string
    passed*: bool
    detail*: string

proc stubSession*(script: seq[string], registerPipeline: bool = true): Session =
  ## Session whose generator returns the scripted responses in order.
  var s = newSession(".")
  var idx = 0
  s.genStub = proc(userMsg: string): string =
    if idx < script.len:
      let r = script[idx]
      inc idx
      return r
    return "No more scripted responses."
  if registerPipeline:
    s.registerTool("run_pipeline", proc(args: string): string =
      var sess = s
      return pipelineTool(sess, args))
  return s

# ----------------------------------------------------------------------
# Eval 1: Tool calling
# ----------------------------------------------------------------------
proc evalToolCalling*(run: var seq[Check]) =
  # a second [tool] later in the reply (offset > 0) must not crash the parser
  let multi = "[tool] run_pipeline {\"intent\": \"first\"}\nAssistant: OK\nBot: " &
              "[tool] run_pipeline {\"intent\": \"write a short poem about\""
  try:
    let mCalls = parseToolCalls(multi)
    run.add(Check(name: "multi [tool] lines parse without crash",
                  passed: mCalls.len >= 1,
                  detail: "got " & $mCalls.len & " calls"))
  except CatchableError as e:
    run.add(Check(name: "multi [tool] lines parse without crash",
                  passed: false, detail: e.msg))
  var s = stubSession(@[
    "[tool] run_pipeline {\"intent\": \"write a poem about roses\"}",
    "pipeline: poem draft generated",
    "Here is your poem: roses are red."
  ])

  let turn = runHarnessTurn(s, "write a poem about roses")

  run.add(Check(name: "detects tool call in output",
                passed: turn.toolCalls.len == 1,
                detail: "got " & $turn.toolCalls.len & " calls"))
  if turn.toolCalls.len == 1:
    run.add(Check(name: "tool name is run_pipeline",
                  passed: turn.toolCalls[0].name == "run_pipeline",
                  detail: "got '" & turn.toolCalls[0].name & "'"))
    run.add(Check(name: "tool args carry intent",
                  passed: turn.toolCalls[0].args.contains("poem")))
  run.add(Check(name: "loop produced a final text",
                passed: turn.finalText.len > 0,
                detail: "finalText: " & turn.finalText))
  run.add(Check(name: "final text is the model's answer (not fallback)",
                passed: turn.finalText.contains("roses are red"),
                detail: "finalText: " & turn.finalText))
  run.add(Check(name: "executed in 2 iterations (tool + answer)",
                passed: turn.iterations == 2,
                detail: "got " & $turn.iterations))

# ----------------------------------------------------------------------
# Eval 2: Loop termination
# ----------------------------------------------------------------------
proc evalLoopTermination*(run: var seq[Check]) =
  # Enough tool-call responses to fill all iterations (each iteration also
  # consumes one response for the pipeline's internal generation).
  var script: seq[string]
  for i in 0 .. 25:
    script.add("[tool] run_pipeline {\"intent\":\"loop\"}")
  script.add("never reached")

  var s = stubSession(script)
  let turn = runHarnessTurn(s, "loop forever")

  run.add(Check(name: "terminates despite continuous tool calls",
                passed: true,
                detail: "stopped at iter " & $turn.iterations))
  run.add(Check(name: "does not exceed max iterations (" & $MaxToolIterations & ")",
                passed: turn.iterations <= MaxToolIterations,
                detail: "got " & $turn.iterations))
  run.add(Check(name: "marks turn aborted when limit hit",
                passed: turn.aborted,
                detail: "aborted=" & $turn.aborted))

# ----------------------------------------------------------------------
# Eval 3: Session JSONL tree integrity
# ----------------------------------------------------------------------
proc evalSessionLogging*(run: var seq[Check]) =
  var s = stubSession(@[
    "[tool] run_pipeline {\"intent\":\"log me\"}",
    "pipeline: logged",
    "Final response here."
  ])
  discard runHarnessTurn(s, "please log")

  let path = "logs/eval_session_test.jsonl"
  s.saveSession(path)

  if fileExists(path):
    # JSONL: one JSON object per line
    var objs: seq[JsonNode]
    for line in path.lines:
      if line.strip().len > 0:
        try:
          objs.add(parseJson(line))
        except JsonParsingError:
          discard

    run.add(Check(name: "session file has a header line",
                  passed: objs.len >= 1))
    run.add(Check(name: "writes 4 messages (user, tool_call, tool_result, text)",
                  passed: objs.len == 5,
                  detail: "expected 5 objects (header+4 msgs), got " & $objs.len))
    if objs.len == 5:
      let userLine = objs[1]
      let toolCallLine = objs[2]
      let toolResultLine = objs[3]
      let textLine = objs[4]
      run.add(Check(name: "first message is the user request",
                    passed: userLine["role"].str == "user"))
      run.add(Check(name: "tool_call message has stopReason=toolUse",
                    passed: toolCallLine["stopReason"].str == "toolUse"))
      run.add(Check(name: "tool_call contains toolName+args",
                    passed: toolCallLine["content"][0]["toolName"].str == "run_pipeline" and
                              toolCallLine["content"][0]["arguments"].str.len > 0))
      run.add(Check(name: "tool_result references its tool_call",
                    passed: toolResultLine["parentId"].str == toolCallLine["id"].str))
      run.add(Check(name: "final text message role=assistant",
                    passed: textLine["role"].str == "assistant"))
  else:
    run.add(Check(name: "session file written", passed: false, detail: "missing " & path))

# ----------------------------------------------------------------------
# Eval 4: GPU fallback policy (config-gated CPU fallback)
# ----------------------------------------------------------------------
proc evalGpuPolicy*(run: var seq[Check]) =
  # available GPU -> use it regardless
  let avail = GpuReport(status: gpuAvailable, deviceCount: 1, detail: "test")
  run.add(Check(name: "healthy GPU uses configured layers",
                passed: decideGpu(avail, 99, false).decision == gdUseGpu))
  run.add(Check(name: "healthy GPU preserves layer count",
                passed: decideGpu(avail, 42, true).layers == 42))

  # unusable GPU + fallback allowed -> CPU (layers 0)
  let bad = GpuReport(status: gpuUnusable, deviceCount: 0, detail: "requires reset")
  let fallback = decideGpu(bad, 99, allowCpuFallback = true)
  run.add(Check(name: "unusable GPU + allowCpuFallback -> CPU",
                passed: fallback.decision == gdCpuFallback and fallback.layers == 0,
                detail: "decision=" & $fallback.decision & " layers=" & $fallback.layers))

  # unusable GPU + fallback NOT allowed -> blocked
  let blocked = decideGpu(bad, 99, allowCpuFallback = false)
  run.add(Check(name: "unusable GPU + no fallback -> blocked (refuse)",
                passed: blocked.decision == gdBlocked,
                detail: "decision=" & $blocked.decision))

  # no driver found -> same as unusable for policy
  let none = GpuReport(status: gpuUnknown, deviceCount: -1, detail: "no driver")
  run.add(Check(name: "no CUDA driver + allowCpuFallback -> CPU",
                passed: decideGpu(none, 99, true).decision == gdCpuFallback))
  run.add(Check(name: "no CUDA driver + no fallback -> blocked",
                passed: decideGpu(none, 99, false).decision == gdBlocked))

  # safeGpuLayers: VRAM-headroom clamp reads model header (magic 'ggmf' = 0x67676d66)
  let tmpHead = getTempDir() / "nimo_safe_layers_test.bin"
  var blob = newString(2 * 1024 * 1024)  # 2 MiB fake model
  blob[0] = 'f'; blob[1] = 'm'; blob[2] = 'g'; blob[3] = 'g'  # magic 0x67676d66, LE bytes
  blob[16] = char(32)  # n_layer = 32 (little-endian byte 0)
  writeFile(tmpHead, blob)

  let ample = safeGpuLayers(tmpHead, requested = 32, freeVram = 2048)  # ample VRAM
  run.add(Check(name: "ample VRAM keeps requested GPU layers",
                passed: ample == 32, detail: "got " & $ample))
  let tight = safeGpuLayers(tmpHead, requested = 32, freeVram = 1)      # 2MiB model, 1MiB vram
  run.add(Check(name: "tight VRAM clamps GPU layers down",
                passed: tight < 32, detail: "got " & $tight))
  removeFile(tmpHead)

# ----------------------------------------------------------------------
# Eval 5: raw -> quantize -> cache (model_cache)
# ----------------------------------------------------------------------
proc evalModelCache*(run: var seq[Check]) =
  let tmpDir = getTempDir() / "nimo_mcache_test"
  removeDir(tmpDir)
  createDir(tmpDir)

  # fake raw FP16 model file: 24-byte header (magic, v101, vocab 65536,
  # embed 2560, layers 32, dtype 1=F16) + padding
  var blob = newString(256 * 1024)
  blob[0] = 'f'; blob[1] = 'm'; blob[2] = 'g'; blob[3] = 'g'   # magic 0x67676d66 LE
  blob[4] = char(101)                                          # version
  blob[8] = char(0); blob[9] = char(0); blob[10] = char(1)     # n_vocab = 65536
  blob[12] = char(0); blob[13] = char(10)                      # n_embed = 2560
  blob[16] = char(32)                                          # n_layer = 32
  blob[20] = char(1)                                           # data_type = F16 (raw)
  let raw = tmpDir / "raw-f16.bin"
  writeFile(raw, blob)

  let h = readModelHeader(raw)
  run.add(Check(name: "model header parses (magic/version/layers/dtype)",
                passed: h.magic == ModelMagic and h.version == 101 and
                        h.nLayer == 32 and h.dataType == 1,
                detail: "magic=" & $h.magic & " dtype=" & $h.dataType))
  run.add(Check(name: "FP16 header is a raw model, not quantized",
                passed: isRawModel(h) and not isQuantized(h)))

  # deterministic cache path, stable across calls
  let mc = initModelCache(tmpDir / "cache")
  let p1 = mc.quantizedPath(raw, "Q4_K")
  let p2 = mc.quantizedPath(raw, "Q4_K")
  run.add(Check(name: "quantized cache path is deterministic",
                passed: p1 == p2 and p1.contains("q4_k"), detail: p1))
  run.add(Check(name: "different format -> different cache path",
                passed: mc.quantizedPath(raw, "Q4_K") != mc.quantizedPath(raw, "Q5_1")))

  # offline ensureQuantized reports the would-be path and doesn't crash
  let (offPath, offCached) = mc.ensureQuantized(raw, "Q4_K")
  run.add(Check(name: "offline ensureQuantized is safe (no librwkv needed)",
                passed: offPath == p1 and offCached == fileExists(p1),
                detail: offPath))

  # already-quantized raw model is used as-is
  blob[20] = char(12)   # dtype = Q4_K
  let qraw = tmpDir / "raw-q4k.bin"
  writeFile(qraw, blob)
  let (qp, qcached) = mc.ensureQuantized(qraw, "Q4_K")
  run.add(Check(name: "already-quantized model is used directly",
                passed: qp == qraw and qcached,
                detail: qp))

  removeDir(tmpDir)

# ----------------------------------------------------------------------
# Eval 6: context-read -> state -> cache (state_cache / RFC 8000)
# ----------------------------------------------------------------------
proc evalStateCache*(run: var seq[Check]) =
  let tmpDir = getTempDir() / "nimo_scache_test"
  removeDir(tmpDir)
  createDir(tmpDir)

  let modelPath = tmpDir / "model.bin"
  let vocabPath = tmpDir / "vocab.txt"
  # model signature hashes size/mtime/head; make a stable tiny file
  writeFile(modelPath, "fake-model-contents")
  writeFile(vocabPath, "token vocab 65536")

  let sc = initStateCache(tmpDir / "state")
  let k1 = stateCacheKey(modelPath, vocabPath, "User: hi\n\nBot:")
  let k2 = stateCacheKey(modelPath, vocabPath, "User: hi\n\nBot:")
  run.add(Check(name: "state cache key is deterministic",
                passed: k1 == k2 and k1.len == 40, detail: k1))
  let k3 = stateCacheKey(modelPath, vocabPath, "different context")
  run.add(Check(name: "state cache key changes with context",
                passed: k1 != k3))
  let k4 = stateCacheKey(tmpDir / "model2.bin", vocabPath, "User: hi\n\nBot:")
  writeFile(tmpDir / "model2.bin", "different-model-contents")
  run.add(Check(name: "state cache key changes with model file",
                passed: k1 != k4))

  # round-trip save/load + miss behavior
  let state = @[1.0'f32, 2.0, 3.0, 4.0]
  let stPath = sc.statePath(k1)
  saveStateToFile(state, stPath)
  var loaded = newSeq[float32](4)
  run.add(Check(name: "state round-trips through cache file",
                passed: loadStateFromFile(loaded, stPath) and loaded == state))
  var wrongLen = newSeq[float32](8)
  run.add(Check(name: "state load rejects size mismatch",
                passed: not loadStateFromFile(wrongLen, stPath)))
  run.add(Check(name: "state load misses on absent file",
                passed: not loadStateFromFile(loaded, tmpDir / "nope.state.bin")))
  run.add(Check(name: "loadCachedState returns empty on miss",
                passed: sc.loadCachedState(tmpDir / "missing.bin", vocabPath,
                                           "ctx", 4).len == 0))

  removeDir(tmpDir)

# ----------------------------------------------------------------------
# Runner
# ----------------------------------------------------------------------
proc runAllEvals*(): int =
  var run: seq[Check]
  evalToolCalling(run)
  evalLoopTermination(run)
  evalSessionLogging(run)
  evalGpuPolicy(run)
  evalModelCache(run)
  evalStateCache(run)

  echo "\n=== nimo harness evals (stub, no model) ==="
  var passCount = 0
  for c in run:
    let mark = if c.passed: "[PASS]" else: "[FAIL]"
    echo mark & " " & c.name
    if c.detail.len > 0:
      echo "       " & c.detail
    if c.passed: inc passCount
  echo ""
  echo "  " & $passCount & "/" & $run.len & " passed"
  echo "  exit=" & $(if passCount == run.len: 0 else: 1)
  return if passCount == run.len: 0 else: 1

when isMainModule:
  quit(runAllEvals())
