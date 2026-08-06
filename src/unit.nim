## NIMO Unit Test Suite
## Tests the harness loop deterministically with a scripted generator (no real model needed).
## Covers three dimensions from RFC 9300-eval:
##   1. Tool calling   - does the loop detect, dispatch, and feed back tool results?
##   2. Loop termination - does it stop on a final text answer / hit max-iteration guard?
##   3. Session logging - is the JSONL message tree (user -> tool_call -> tool_result -> text) well-formed?

import std/[strutils, os, json]
import ./session_manager, ./pipeline, ./harness, ./gpu, ./rwkv/quant/cache, ./rwkv/state/cache, ./rwkv/model/header, ./session_branch
import ./program, ./engine, ./validate, ./config, ./model_evals, ./jules
import ./memory, ./fiaas

type
  Check* = object
    name*: string
    passed*: bool
    detail*: string

proc newSessionWithMockGen*(script: seq[string], registerPipeline: bool = true): (Session, GenerateFn) =
  ## Returns a REAL session (real message tree, tools, bookkeeping) plus a mock
  ## generator that returns the scripted replies in order. Only the
  ## model-generation is mocked, and it is injected at call sites (passed to
  ## runHarnessTurn/generateTurn) — nothing about the session itself is stubbed.
  var s = newSession(".")
  var idx = 0
  let gen = proc(userMsg: string): string =
    if idx < script.len:
      let r = script[idx]
      inc idx
      return r
    return "No more scripted responses."
  if registerPipeline:
    s.registerTool("run_pipeline", proc(args: string): string =
      var sess = s
      return pipelineTool(sess, args, gen))
  return (s, gen)

# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
# Eval 1: Orchestrator + engine turn
# ----------------------------------------------------------------------
proc evalToolCalling*(run: var seq[Check]) =
  var (s, gen) = newSessionWithMockGen(@[
    "Once upon a time, roses were red.",
    "Roses are red, violets are blue."
  ])
  let turn = runHarnessTurn(s, "write a poem about roses", gen)

  run.add(Check(name: "orchestrator compiles goal into a plan",
                passed: s.messages.len >= 2,
                detail: "msgs=" & $s.messages.len))
  run.add(Check(name: "turn produced a final text",
                passed: turn.finalText.len > 0,
                detail: "finalText: " & turn.finalText))
  run.add(Check(name: "final text is the model's answer",
                passed: turn.finalText.contains("roses") or turn.finalText.contains("Once"),
                detail: "finalText: " & turn.finalText))
  run.add(Check(name: "engine executed the plan steps",
                passed: turn.iterations > 0,
                detail: "iterations=" & $turn.iterations))
  run.add(Check(name: "plan node recorded in history",
                passed: s.messages[1].content.len > 0 and
                        s.messages[1].content[0].kind == ckPlan,
                detail: "kind=" & $s.messages[1].content[0].kind))
# ----------------------------------------------------------------------
# Eval 2: Engine max-steps guard
# ----------------------------------------------------------------------
proc evalLoopTermination*(run: var seq[Check]) =
  var script: seq[string]
  for i in 0 .. 25:
    script.add("step output " & $i)

  var (s, gen) = newSessionWithMockGen(script)
  let turn = runHarnessTurn(s, "write a story", gen, maxIterations = 3)

  run.add(Check(name: "terminates despite many planned steps",
                passed: true,
                detail: "stopped at iter " & $turn.iterations))
  run.add(Check(name: "does not exceed max iterations (3)",
                passed: turn.iterations <= 3,
                detail: "got " & $turn.iterations))
  run.add(Check(name: "marks turn aborted when limit hit",
                passed: turn.aborted,
                detail: "aborted=" & $turn.aborted))

# ----------------------------------------------------------------------
# Eval 3: Session JSONL tree integrity
# ----------------------------------------------------------------------
proc evalSessionLogging*(run: var seq[Check]) =
  var (s, gen) = newSessionWithMockGen(@[
    "extracted context",
    "final answer here."
  ])
  discard runHarnessTurn(s, "please log", gen)

  let path = "logs/eval_session_test.jsonl"
  s.saveSession(path)

  if fileExists(path):
    var objs: seq[JsonNode]
    for line in path.lines:
      if line.strip().len > 0:
        try:
          objs.add(parseJson(line))
        except JsonParsingError:
          discard

    run.add(Check(name: "session file has a header line",
                  passed: objs.len >= 1))
    run.add(Check(name: "writes at least 3 objects (header + user + plan)",
                  passed: objs.len >= 3,
                  detail: "expected >= 3 objects, got " & $objs.len))
    if objs.len >= 3:
      let userLine = objs[1]
      let planLine = objs[2]
      run.add(Check(name: "first message is the user request",
                    passed: userLine["role"].str == "user"))
      run.add(Check(name: "plan node recorded with steps",
                    passed: planLine["content"][0]["type"].str == "plan" and
                            planLine["content"][0]["text"].str.len > 0))
      run.add(Check(name: "plan node chains to user message",
                    passed: planLine["parentId"].str == userLine["id"].str))
  else:
    run.add(Check(name: "session file written", passed: false, detail: "missing " & path))

# ----------------------------------------------------------------------
# Eval 4: GPU policy (explicit only — no fallbacks)
# ----------------------------------------------------------------------
proc evalGpuPolicy*(run: var seq[Check]) =
  # available GPU -> use it
  let avail = GpuReport(status: gpuAvailable, deviceCount: 1, detail: "test")
  run.add(Check(name: "healthy GPU uses configured layers",
                passed: decideGpu(avail, 99).decision == gdUseGpu))
  run.add(Check(name: "healthy GPU preserves layer count",
                passed: decideGpu(avail, 42).layers == 42))

  # unusable GPU -> blocked (no fallback to CPU)
  let bad = GpuReport(status: gpuUnusable, deviceCount: 0, detail: "requires reset")
  run.add(Check(name: "unusable GPU -> blocked",
                passed: decideGpu(bad, 99).decision == gdBlocked,
                detail: "decision=" & $decideGpu(bad, 99).decision))

  # no driver found -> blocked
  let none = GpuReport(status: gpuUnknown, deviceCount: -1, detail: "no driver")
  run.add(Check(name: "no CUDA driver -> blocked",
                passed: decideGpu(none, 99).decision == gdBlocked))

  # layer derivation: from model shape (no magic default), clamped by VRAM
  let tmpDir = getTempDir() / "nimo_gpu_layers_test"
  removeDir(tmpDir)
  createDir(tmpDir)
  # fake 32-layer FP16 model header (magic ggmf, v101, vocab 65536, embed 2560)
  var blob = newString(64 * 1024)
  blob[0] = 'f'; blob[1] = 'm'; blob[2] = 'g'; blob[3] = 'g'
  blob[4] = char(101)
  blob[8] = char(0); blob[9] = char(0); blob[10] = char(1)
  blob[12] = char(0); blob[13] = char(10)
  blob[16] = char(32)   # n_layer = 32
  blob[20] = char(1)    # F16
  let fakeModel = tmpDir / "fake32.bin"
  writeFile(fakeModel, blob)

  # auto mode (-1) resolves to the model's own layer count (32)
  run.add(Check(name: "auto gpuLayers derives from model nLayer",
                passed: resolveGpuLayers(fakeModel, -1) == 32,
                detail: "layers=" & $resolveGpuLayers(fakeModel, -1)))
  # explicit cap higher than model -> clamped to model
  run.add(Check(name: "gpuLayers cap is clamped to model layers",
                passed: resolveGpuLayers(fakeModel, 99) == 32,
                detail: "layers=" & $resolveGpuLayers(fakeModel, 99)))
  # explicit 0 -> CPU only
  run.add(Check(name: "gpuLayers 0 means CPU",
                passed: resolveGpuLayers(fakeModel, 0) == 0))
  # unreadable model -> -1 (caller treats as failure)
  run.add(Check(name: "unreadable model header -> -1",
                passed: resolveGpuLayers(tmpDir / "nope.bin", -1) == -1))

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
# Eval 7: Plan artifact (RFC 3500) — construction, navigation, persistence
# ----------------------------------------------------------------------
proc evalPlanArtifact*(run: var seq[Check]) =
  var p = newPlan("write a story")
  run.add(Check(name: "new plan starts running at cursor 0",
                passed: p.status == psRunning and p.cursor == 0 and
                        p.goal == "write a story",
                detail: p.id))

  p.addStep(generateStep("outline", "premise: a robot gardener"))
  p.addStep(extractStep("characters", "outline", "the characters"))
  p.addStep(reportStep("outline ready"))

  run.add(Check(name: "plan has the steps added",
                passed: p.steps.len == 3 and p.steps[1].kind == skExtract and
                        p.steps[2].kind == skReport))
  run.add(Check(name: "currentStep follows the cursor",
                passed: p.currentStep.kind == skGenerate))

  p.advance()
  run.add(Check(name: "advance moves the cursor",
                passed: p.cursor == 1 and p.currentStep.kind == skExtract))
  p.advance(); p.advance()
  run.add(Check(name: "plan done at end, status set",
                passed: p.isDone and p.status == psDone))

  # splice: data-driven fan-out inserts steps at a position
  var p2 = newPlan("loops")
  p2.addStep(extractStep("extract-chars", "outline", "characters"))
  p2.addStep(reportStep("end"))
  p2.splice(@[generateStep("wiki-a", "events for A"),
              generateStep("wiki-b", "events for B")], 1)
  run.add(Check(name: "splice inserts sub-steps at the position",
                passed: p2.steps.len == 4 and p2.steps[1].name == "wiki-a" and
                        p2.steps[2].name == "wiki-b" and
                        p2.steps[3].kind == skReport))

  # persistence round-trip
  let tmp = getTempDir() / "nimo_plan_test"
  removeDir(tmp); createDir(tmp)
  let path = tmp / "plan.json"
  p.save(path)
  let loaded = loadPlan(path)
  run.add(Check(name: "plan save/load round-trips steps and goal",
                passed: loaded.goal == p.goal and loaded.steps.len == p.steps.len and
                        loaded.steps[1].kind == skExtract and
                        loaded.steps[1].source == "outline",
                detail: path))
  run.add(Check(name: "plan load restores the cursor (resume point)",
                passed: loaded.cursor == p.cursor,
                detail: "cursor=" & $loaded.cursor))
  let cp = p.checkpoint()
  run.add(Check(name: "checkpoint carries id + cursor + status",
                passed: cp["id"].str == p.id and cp["cursor"].getInt == p.cursor))
  removeDir(tmp)

# ----------------------------------------------------------------------
# Eval 8: Engine (RFC 3600) — execute, abort, interrupt, resume
# ----------------------------------------------------------------------
proc evalEngine*(run: var seq[Check]) =
  # scripted generator: deterministic model stand-in
  var calls = newSeq[string]()
  let gen: GenerateFn = proc(prompt: string): string =
    calls.add(prompt)
    "generated:" & prompt

  var p = newPlan("run me")
  p.addStep(generateStep("step1", "hello"))
  p.addStep(extractStep("step2", "outline", "characters", "Kael"))
  p.addStep(reportStep("done"))

  var sinkText = ""
  let r = p.run(gen, sink = proc(t: string) = sinkText.add(t), maxSteps = 10)
  run.add(Check(name: "engine completes a small plan",
                passed: r.completed and r.stepsRun == 3 and p.status == psDone,
                detail: "stepsRun=" & $r.stepsRun))
  run.add(Check(name: "generate step calls the model with context",
                passed: calls.len == 2 and calls[0] == "hello",
                detail: calls[0]))
  run.add(Check(name: "extract builds a pointed prompt (filter/source/for)",
                passed: calls[1].contains("characters") and
                        calls[1].contains("outline") and calls[1].contains("Kael")))
  run.add(Check(name: "step outputs are recorded on the plan",
                passed: p.steps[0].output.startsWith("generated:") and
                        p.steps[1].output.len > 0))
  run.add(Check(name: "report emits a checkpoint to the sink",
                passed: sinkText.contains("done") and sinkText.contains("▶")))

  # validate gate: short text fails, long passes
  var pv = newPlan("validate")
  pv.addStep(validateStep("check", "too short"))
  let rv = pv.run(gen, maxSteps = 10)
  run.add(Check(name: "validate fails short text and records issues",
                passed: pv.steps[0].status == ssFailed and
                        pv.steps[0].output.contains("passed=false")))

  # write step creates the file
  let tmp = getTempDir() / "nimo_engine_test"
  removeDir(tmp); createDir(tmp)
  let fpath = tmp / "out.txt"
  var pw = newPlan("write")
  pw.addStep(writeStep("save", fpath, "hello file"))
  discard pw.run(gen, maxSteps = 10)
  run.add(Check(name: "write step creates the target file",
                passed: fileExists(fpath) and readFile(fpath) == "hello file"))

  # Templates commonly leave Validate and Write inputs implicit: both consume
  # the immediately preceding generated artifact.
  let derivedPath = tmp / "derived.txt"
  var derived = newPlan("derived data flow")
  derived.addStep(generateStep("draft", "focused text"))
  derived.addStep(writeStep("persist draft", derivedPath))
  discard derived.run(gen, maxSteps = 10)
  run.add(Check(name: "write without content persists the previous step output",
                passed: fileExists(derivedPath) and
                        readFile(derivedPath) == "generated:focused text"))

  # max-steps guard: a plan that never terminates aborts
  var pl = newPlan("looper")
  for i in 0 .. 9: pl.addStep(generateStep("g" & $i, "x"))
  let rl = pl.run(gen, maxSteps = 3)
  run.add(Check(name: "engine aborts a plan that exceeds max steps",
                passed: rl.aborted and rl.stoppedAt <= 3 and
                        pl.status != psDone, detail: "stoppedAt=" & $rl.stoppedAt))

  # interrupt + resume from the stopped cursor
  var pi = newPlan("interruptible")
  pi.addStep(generateStep("a", "1"))
  pi.addStep(generateStep("b", "2"))
  pi.addStep(generateStep("c", "3"))
  var ticks = 0
  let ri = pi.run(gen, interrupt = proc (): bool =
    inc ticks
    ticks > 1, maxSteps = 10)
  run.add(Check(name: "interrupt stops the engine and pauses the plan",
                passed: ri.interrupted and pi.status == psInterrupted and
                        ri.stoppedAt == 1, detail: "stoppedAt=" & $ri.stoppedAt))
  let r2 = pi.run(gen, maxSteps = 10)
  run.add(Check(name: "resume continues from the interrupted cursor",
                passed: r2.completed and pi.cursor == pi.steps.len and
                        pi.steps[1].output.len > 0 and pi.steps[2].output.len > 0))
  removeDir(tmp)

# ----------------------------------------------------------------------
# Eval 9: deterministic validation (validate.nim)
# ----------------------------------------------------------------------
proc evalValidate*(run: var seq[Check]) =
  run.add(Check(name: "countWords counts words",
                passed: validate.countWords("one two three") == 3 and
                        validate.countWords("") == 0))
  run.add(Check(name: "countWords handles unicode/emoji",
                passed: validate.countWords("This is a 🤖 test.") == 4 and
                        validate.countWords("你好 🚀 world") == 1))
  run.add(Check(name: "countLines counts non-empty lines",
                passed: validate.countLines("a\n\nb\nc") == 3))
  run.add(Check(name: "countLines handles trailing newlines",
                passed: validate.countLines("a\n\n\n\n\n\n\n") == 1))
  run.add(Check(name: "empty string edge cases",
                passed: validate.countWords("") == 0 and
                        validate.countLines("") == 0 and
                        validateText("").wordCount == 0 and
                        validateText("").paragraphCount == 0 and
                        validateText("").repeatingSegments == 0))
  let short = validateText("too short")
  run.add(Check(name: "validateText fails short text",
                passed: not short.passed and short.wordCount == 2 and
                        short.issues.len > 0))
  var long = "The fierce wind tore across the empty valley.\n" &
             "Kael tightened his coat and watched the storm roll in.\n" &
             "The old lighthouse flickered once, then steadied.\n" &
             "Far below, the harbor lights began to blink awake.\n" &
             "He had not expected to return here, not after all this time.\n" &
             "The sea swallowed the horizon in a single grey breath.\n"
  let ok = validateText(long, minWords = 10, minParagraphs = 5)
  run.add(Check(name: "validateText passes a long multi-paragraph text",
                passed: ok.passed))
  let repeats = validateText("a b c a b c a b c")
  run.add(Check(name: "validateText catches repeating segments",
                passed: repeats.repeatingSegments == 1))
  let norepeats = validateText("a b c d e f")
  run.add(Check(name: "validateText handles non-repeating segments",
                passed: norepeats.repeatingSegments == 0))

# ----------------------------------------------------------------------
# Eval 10: streaming boundary (RFC 3600)
# ----------------------------------------------------------------------
proc evalStreaming*(run: var seq[Check]) =
  var s = newSession(".")
  var chunks: seq[string]
  let reply = s.generateTurnStream("hello", proc(text: string) = chunks.add(text),
    generate = proc(_: string): string = "streamed reply")
  run.add(Check(name: "streaming generation returns the complete reply",
                passed: reply == "streamed reply"))
  run.add(Check(name: "streaming generation forwards scripted output to its sink",
                passed: chunks == @["streamed reply"], detail: chunks.join("|")))

# ----------------------------------------------------------------------
# Eval 11: harness turn primitives (Phase 0 decomposed loop)
# ----------------------------------------------------------------------
proc evalTurnPrimitives*(run: var seq[Check]) =
  # recordTurnStart records the user message and returns the root parent id.
  var s = newSession(".")
  let rootId = recordTurnStart(s, "hello there")
  run.add(Check(name: "recordTurnStart records a user message",
                passed: s.messages.len == 1 and s.messages[0].role == mrUser and
                        s.messages[0].id == rootId,
                detail: "root=" & rootId))

  # parseReply extracts tool calls from the 3 modeled forms.
  let calls = parseReply("[tool] run_pipeline {\"intent\": \"one\"}")
  run.add(Check(name: "parseReply extracts [tool] calls",
                passed: calls.len == 1 and calls[0].name == "run_pipeline",
                detail: "calls=" & $calls.len))
  let calls2 = parseReply("{\"name\": \"x\", \"arguments\": {\"k\": 1}}")
  run.add(Check(name: "parseReply handles bare JSON calls",
                passed: calls2.len == 1 and calls2[0].name == "x",
                detail: "calls=" & $calls2.len))

  # runCalls executes against registered tools and records call+result.
  var s2 = newSession(".")
  let root2 = recordTurnStart(s2, "run it")
  s2.registerTool("ping", proc(_: string): string = "pong")
  let (feed, lastParent) = runCalls(s2, @[ToolCall(name: "ping", args: "{}")], root2)
  run.add(Check(name: "runCalls records tool_call then tool_result",
                passed: s2.messages.len == 3 and
                        s2.messages[2].role == mrToolResult and
                        s2.messages[2].parentId == s2.messages[1].id,
                detail: "msgs=" & $s2.messages.len))
  run.add(Check(name: "runCalls returns feedback + lastParentId",
                passed: feed.contains("pong") and feed.contains("[tool_result for ping]") and
                        lastParent == s2.messages[1].id,
                detail: lastParent))

  # buildNextContext strips markers and carries feedback.
  let ctx = buildNextContext("[tool] run_pipeline {\"x\":1}", "[tool_result for ping]\npong\n\n")
  run.add(Check(name: "buildNextContext strips markers, keeps feedback",
                passed: (not ctx.contains("[tool]")) and ctx.contains("pong") and
                        ctx.contains("Now answer"),
                detail: ctx))

# ----------------------------------------------------------------------
# Eval 17: model evals
# ----------------------------------------------------------------------
proc evalModelEvals*(run: var seq[Check]) =
  # Test that model evals compile and run without crashing
  # (Real model probes require GPU - this tests the deterministic planner part)
  let result = runPlannerEval(5)
  run.add(Check(name: "model evals: planner compilation works",
                passed: result.trials > 0 and result.rate >= 0.0,
                detail: "rate=" & $result.rate & " trials=" & $result.trials))

proc evalJules*(run: var seq[Check]) =
  # Pure helpers for the jules CLI, offline (no network).
  # stateIcon maps known states to empjiji; unknown stays neutral.
  run.add(Check(name: "jules: state icons",
                passed: stateIcon("COMPLETED") == "✅" and
                        stateIcon("RUNNING") == "▶" and
                        stateIcon("archived") == "🗄️" and
                        stateIcon("weird") == "○",
                detail: "icons=" & stateIcon("COMPLETED") & "/" & stateIcon("RUNNING") & "/" & stateIcon("weird")))

  # shorten collapses newlines and truncates with ellipsis.
  run.add(Check(name: "jules: shorten collapses + truncates",
                passed: shorten("a\nb\nc") == "a b c" and
                        shorten("0123456789", 4) == "0123…" and
                        shorten("short") == "short",
                detail: "got='" & shorten("a\nb\nc") & "'"))

  # extractPrs pulls pullRequest urls out of session outputs.
  let sess = parseJson("""{"id":"x","outputs":[
    {"pullRequest":{"url":"https://github.com/CodeDoes/nimo/pull/1"}},
    {"something":true},
    {"pullRequest":{"url":"https://github.com/CodeDoes/roco_ai/pull/28"}}
  ]}""")
  let prs = extractPrs(sess)
  run.add(Check(name: "jules: extractPrs picks urls",
                passed: prs == @["https://github.com/CodeDoes/nimo/pull/1",
                                 "https://github.com/CodeDoes/roco_ai/pull/28"],
                detail: "got=" & $prs))

  # activityLine reads agentMessaged text (the key shape used by the CLI).
  let act = parseJson("""{"createTime":"2026-08-05T06:29:52Z","originator":"agent",
    "agentMessaged":{"agentMessage":"let us look at the plan"}}""")
  let line = activityLine(act)
  run.add(Check(name: "jules: activityLine shows agent message",
                passed: "💬" in line and "let us look" in line and "[agent]" in line,
                detail: "line='" & line & "'"))

  # resolveKey strips quotes from an inline/dotenv value (never the raw secret).
  run.add(Check(name: "jules: resolveKey strips quotes",
                passed: resolveKey(inline = "\"AQabc…\"") == "AQabc…" and
                        resolveKey(inline = "'k3'") == "k3" and
                        resolveKey(inline = "k4") == "k4",
                detail: "stripped=" & resolveKey(inline = "\"AQabc…\"")))

  # feedbackHint tells the user whether to approve a plan or answer a question.
  let planWait = parseJson("""[
     {"planGenerated":{}},
     {"progressUpdated":{}}]
  """)
  let answered = parseJson("""[
     {"planGenerated":{}},
     {"planApproved":{}},
     {"progressUpdated":{}}]
  """)
  let question = parseJson("""[{"agentMessaged":{"agentMessage":"which dir?"}}]""")
  run.add(Check(name: "jules: feedbackHint distinguishes plan vs question",
                passed: "jules approve" in feedbackHint("s1", planWait) and
                        "jules send" in feedbackHint("s1", answered) and
                        "jules send" in feedbackHint("s1", question) and
                        "jules approve" notin feedbackHint("s1", answered),
                detail: "plan=" & $feedbackHint("s1", planWait).splitLines()[0] &
                         " | answered=" & $feedbackHint("s1", answered).splitLines()[0]))

  # planNeedsApproval / planText / lastAgentMessage power the supervisor.
  let planAct = parseJson("""[{"planGenerated":{"plan":{"steps":[
      {"title":"Make build","description":"wrap nimble commands"},
      {"title":"Run unit","description":"nim c -d:harnessOffline"}]}}}]""")
  let approvedAct = parseJson("""[{"planGenerated":{"plan":{}}},{"planApproved":{}}]""")
  let agentQ = parseJson("""[{"agentMessaged":{"agentMessage":"please pick a target"}}]""")
  run.add(Check(name: "jules: supervisor helpers (plan/approve/question)",
                passed: planNeedsApproval(planAct) and
                        not planNeedsApproval(approvedAct) and
                        "Make build" in planText(planAct) and
                        "nim c -d:harnessOffline" in planText(planAct) and
                        lastAgentMessage(agentQ) == "please pick a target",
                detail: "needsApproval=" & $planNeedsApproval(planAct) &
                         " plan=" & planText(planAct).replace("\n", "/")))

# ----------------------------------------------------------------------
# Eval 19: memory.nim (FIAAS + lookupMemory)
# ----------------------------------------------------------------------
proc evalMemory*(run: var seq[Check]) =
  let tmp = getTempDir() / "nimo_memory_test"
  removeDir(tmp); createDir(tmp)
  let memFile = tmp / ".nimo" / "memory" / "memories.json"

  var store = newMemoryStore()
  let id1 = store.addMemory("Roses are red.", category="poem")
  let id2 = store.addMemory("Violets are blue.", category="poem")
  let id3 = store.addMemory("Apples are tasty.", category="food")

  run.add(Check(name: "memory addEntry assigns unique ids",
                passed: id1 != id2 and id1.len > 0, detail: id1))

  let searchRes = store.searchMemory("Roses")
  run.add(Check(name: "memory search retrieves closest match",
                passed: searchRes.len > 0 and "Roses" in searchRes[0],
                detail: "found " & $searchRes.len))

  store.saveMemory(memFile)
  run.add(Check(name: "memory saveToFile writes to correct path",
                passed: fileExists(memFile), detail: memFile))

  var store2 = newMemoryStore()
  let loaded = store2.loadMemory(memFile)
  run.add(Check(name: "memory loadFromFile loads entries",
                passed: loaded and store2.fiaas.count() == 3))

  let found = store2.searchMemory("Violets")
  run.add(Check(name: "loaded memory works with search",
                passed: found.len > 0 and ("Violets" in found[0] or "Roses" in found[0]),
                detail: (if found.len > 0: found[0] else: "")))

  # lookupMemory with different filters
  let ws = tmp
  run.add(Check(name: "lookupMemory returns empty for empty filter",
                passed: lookupMemory("", ws) == ""))
  run.add(Check(name: "lookupMemory returns empty for no match",
                passed: lookupMemory("nonexistent", ws) == ""))
  run.add(Check(name: "lookupMemory returns relevant context",
                passed: lookupMemory("Apples", ws).contains("Apples are tasty.")))

  removeDir(tmp)

# ----------------------------------------------------------------------
# Eval 20: session_branch.nim (Branch message persistence and merging)
# ----------------------------------------------------------------------
proc evalSessionBranching*(run: var seq[Check]) =
  let tmp = getTempDir() / "nimo_branch_test"
  removeDir(tmp); createDir(tmp)
  let branchFile = tmp / "branches.json"

  # 1. Test creation and message preservation
  var sb = newSessionBranch()
  let parentId = "msg_original_parent"
  let bId = sb.addBranch(parentId)

  run.add(Check(name: "branch creation and parent retention",
                passed: bId.len > 0 and sb.getBranch(0).parentId == parentId,
                detail: "branchId=" & bId))

  var msg1: Message
  msg1.id = "msg_branch_1"
  msg1.parentId = parentId
  msg1.timestamp = "2026-08-06T12:00:00"
  msg1.role = mrUser
  msg1.content = @[ContentPart(kind: ckText, text: "hello branch")]

  sb.addMessageToBranch(msg1)
  run.add(Check(name: "message added to branch",
                passed: sb.getBranch(0).messages.len == 1 and
                        sb.getBranch(0).messages[0].id == "msg_branch_1"))

  # 2. Test save/load of branch data (message persistence)
  sb.saveBranch(branchFile)
  run.add(Check(name: "branch file saved",
                passed: fileExists(branchFile)))

  var sb2 = newSessionBranch()
  let loaded = sb2.loadBranch(branchFile)
  run.add(Check(name: "branch file loaded successfully",
                passed: loaded))
  run.add(Check(name: "branch messages restored completely",
                passed: sb2.branches.len == 1 and
                        sb2.branches[0].messages.len == 1 and
                        sb2.branches[0].messages[0].id == "msg_branch_1" and
                        sb2.branches[0].messages[0].content[0].text == "hello branch"))

  # 3. Test merging a branch into main session (with ID clash resolution/mapping)
  var mainSess = newSession(".")
  discard mainSess.addText("root user msg", "", isThinking = false) # msg_0

  let mergeResult = mainSess.mergeBranch(sb2, bId)
  run.add(Check(name: "merge branch success message",
                passed: mergeResult.contains("Successfully merged 1 messages")))

  run.add(Check(name: "merged message is in main session messages",
                passed: mainSess.messages.len == 2 and
                        mainSess.messages[1].role == mrUser and
                        mainSess.messages[1].content[0].text == "hello branch"))

  run.add(Check(name: "merged message has parent correctly resolved",
                passed: mainSess.messages[1].parentId == parentId,
                detail: "parentId=" & mainSess.messages[1].parentId))

  removeDir(tmp)

# ----------------------------------------------------------------------
# Runner
# ----------------------------------------------------------------------
proc runAllEvals*(): int =
  var run: seq[Check]
  evalToolCalling(run)
  evalLoopTermination(run)
  evalSessionLogging(run)
  evalTurnPrimitives(run)
  evalGpuPolicy(run)
  evalModelCache(run)
  evalStateCache(run)
  evalPlanArtifact(run)
  evalEngine(run)
  evalValidate(run)
  evalStreaming(run)
  evalModelEvals(run)
  evalJules(run)
  evalMemory(run)
  evalSessionBranching(run)

  echo "\n=== nimo unit tests (stub, no model) ==="
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
