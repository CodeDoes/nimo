## NIMO Unit Test Suite
## Tests the harness loop deterministically with a scripted generator (no real model needed).
## Covers three dimensions from RFC 9300-eval:
##   1. Orchestrator+engine — interpret goal -> plan -> engine.run -> report
##   2. Engine termination  — max-steps guard aborts long plans
##   3. Session logging     — JSONL tree (user -> plan -> steps -> report)

import std/[strutils, os, times, json]
import ./session_manager, ./pipeline, ./harness, ./gpu, ./rwkv/quant/cache, ./rwkv/state/cache, ./rwkv/model/header
import ./program, ./engine, ./validate, ./config, ./orchestrator

type
  Check* = object
    name*: string
    passed*: bool
    detail*: string

proc newSessionWithMockGen*(script: seq[string], registerPipeline: bool = true): (Session, GenerateFn) =
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
  let turn = runHarnessTurn(s, "generate many steps", gen)

  run.add(Check(name: "terminates despite many planned steps",
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
  let avail = GpuReport(status: gpuAvailable, deviceCount: 1, detail: "test")
  run.add(Check(name: "healthy GPU uses configured layers",
                passed: decideGpu(avail, 99).decision == gdUseGpu))
  run.add(Check(name: "healthy GPU preserves layer count",
                passed: decideGpu(avail, 42).layers == 42))

  let bad = GpuReport(status: gpuUnusable, deviceCount: 0, detail: "requires reset")
  run.add(Check(name: "unusable GPU -> blocked",
                passed: decideGpu(bad, 99).decision == gdBlocked,
                detail: "decision=" & $decideGpu(bad, 99).decision))

  let none = GpuReport(status: gpuUnknown, deviceCount: -1, detail: "no driver")
  run.add(Check(name: "no CUDA driver -> blocked",
                passed: decideGpu(none, 99).decision == gdBlocked))

# ----------------------------------------------------------------------
# Eval 5: raw -> quantize -> cache (model_cache)
# ----------------------------------------------------------------------
proc evalModelCache*(run: var seq[Check]) =
  let tmpDir = getTempDir() / "nimo_mcache_test"
  removeDir(tmpDir)
  createDir(tmpDir)

  var blob = newString(256 * 1024)
  blob[0] = 'f'; blob[1] = 'm'; blob[2] = 'g'; blob[3] = 'g'
  blob[4] = char(101)
  blob[8] = char(0); blob[9] = char(0); blob[10] = char(1)
  blob[12] = char(0); blob[13] = char(10)
  blob[16] = char(32)
  blob[20] = char(1)
  let raw = tmpDir / "raw-f16.bin"
  writeFile(raw, blob)

  let h = readModelHeader(raw)
  run.add(Check(name: "model header parses (magic/version/layers/dtype)",
                passed: h.magic == ModelMagic and h.version == 101 and
                        h.nLayer == 32 and h.dataType == 1,
                detail: "magic=" & $h.magic & " dtype=" & $h.dataType))
  run.add(Check(name: "FP16 header is a raw model, not quantized",
                passed: isRawModel(h) and not isQuantized(h)))

  let mc = initModelCache(tmpDir / "cache")
  let p1 = mc.quantizedPath(raw, "Q4_K")
  let p2 = mc.quantizedPath(raw, "Q4_K")
  run.add(Check(name: "quantized cache path is deterministic",
                passed: p1 == p2 and p1.contains("q4_k"), detail: p1))
  run.add(Check(name: "different format -> different cache path",
                passed: mc.quantizedPath(raw, "Q4_K") != mc.quantizedPath(raw, "Q5_1")))

  let (offPath, offCached) = mc.ensureQuantized(raw, "Q4_K")
  run.add(Check(name: "offline ensureQuantized is safe (no librwkv needed)",
                passed: offPath == p1 and offCached == fileExists(p1),
                detail: offPath))

  blob[20] = char(12)
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

  var p2 = newPlan("loops")
  p2.addStep(extractStep("extract-chars", "outline", "characters"))
  p2.addStep(reportStep("end"))
  p2.splice(@[generateStep("wiki-a", "events for A"),
              generateStep("wiki-b", "events for B")], 1)
  run.add(Check(name: "splice inserts sub-steps at the position",
                passed: p2.steps.len == 4 and p2.steps[1].name == "wiki-a" and
                        p2.steps[2].name == "wiki-b" and
                        p2.steps[3].kind == skReport))

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

  var pv = newPlan("validate")
  pv.addStep(validateStep("check", "too short"))
  let rv = pv.run(gen, maxSteps = 10)
  run.add(Check(name: "validate fails short text and records issues",
                passed: pv.steps[0].status == ssFailed and
                        pv.steps[0].output.contains("passed=false")))

  let tmp = getTempDir() / "nimo_engine_test"
  removeDir(tmp); createDir(tmp)
  let fpath = tmp / "out.txt"
  var pw = newPlan("write")
  pw.addStep(writeStep("save", fpath, "hello file"))
  discard pw.run(gen, maxSteps = 10)
  run.add(Check(name: "write step creates the target file",
                passed: fileExists(fpath) and readFile(fpath) == "hello file"))

  var pl = newPlan("looper")
  for i in 0 .. 9: pl.addStep(generateStep("g" & $i, "x"))
  let rl = pl.run(gen, maxSteps = 3)
  run.add(Check(name: "engine aborts a plan that exceeds max steps",
                passed: rl.aborted and rl.stoppedAt <= 3 and
                        pl.status != psDone, detail: "stoppedAt=" & $rl.stoppedAt))

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
  run.add(Check(name: "countLines counts non-empty lines",
                passed: validate.countLines("a\n\nb\nc") == 3))
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
                passed: repeats.repeatingSegments > 0))

# ----------------------------------------------------------------------
# Eval 10: harness turn primitives
# ----------------------------------------------------------------------
proc evalTurnPrimitives*(run: var seq[Check]) =
  var s = newSession(".")
  let rootId = recordTurnStart(s, "hello there")
  run.add(Check(name: "recordTurnStart records a user message",
                passed: s.messages.len == 1 and s.messages[0].role == mrUser and
                        s.messages[0].id == rootId,
                detail: "root=" & rootId))

  let calls = parseReply("test")
  run.add(Check(name: "parseReply returns empty for non-tool text",
                passed: calls.len == 0))

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

  let ctx = buildNextContext("[tool] run_pipeline {}", "[tool_result for ping]\npong\n\n")
  run.add(Check(name: "buildNextContext strips markers, keeps feedback",
                passed: (not ctx.contains("[tool]")) and ctx.contains("pong") and
                        ctx.contains("Now answer"),
                detail: ctx))

# ----------------------------------------------------------------------
# Eval 11: orchestrator — natural language goal -> plan
# ----------------------------------------------------------------------
proc evalOrchestrator*(run: var seq[Check]) =
  run.add(Check(name: "matchIntent: poem",
                passed: matchIntent("write a poem about roses") == itPoem))
  run.add(Check(name: "matchIntent: story",
                passed: matchIntent("write a story about a lighthouse") == itStory))
  run.add(Check(name: "matchIntent: chapter",
                passed: matchIntent("make chapter 3 about Kael") == itChapter))
  run.add(Check(name: "matchIntent: remember",
                passed: matchIntent("remember that the sky is blue") == itMemory))
  run.add(Check(name: "matchIntent: falls back to answer",
                passed: matchIntent("what is the capital of France") == itAnswer))

  let story = interpret("write a story about a lighthouse")
  run.add(Check(name: "interpret: keeps the goal verbatim",
                passed: story.goal == "write a story about a lighthouse",
                detail: story.goal))
  run.add(Check(name: "interpret: story plan has generate + write + report",
                passed: story.steps.len == 4 and
                        story.steps[1].kind == skGenerate and
                        story.steps[1].skill == "output:story" and
                        story.steps[2].kind == skWrite and
                        story.steps[3].kind == skReport,
                detail: "steps=" & $story.steps.len))
  run.add(Check(name: "interpret: answer is just generate + report",
                passed: interpret("hi").steps.len == 2 and
                        interpret("hi").steps[0].kind == skGenerate))
  run.add(Check(name: "interpret: memory writes a memory file",
                passed: interpret("remember the plan").steps[2].path == "memory.md"))

# ----------------------------------------------------------------------
# Eval 12: planner-emission compilation
# ----------------------------------------------------------------------
proc evalEmission*(run: var seq[Check]) =
  let emission =
    """[step] extract {"source": "memory", "filter": "the story so far"}
[step] generate {"skill": "output:story", "context": "premise: a lighthouse"}
Some prose the planner should not include.
[step] report {"title": "story ready"}
{"step": "write", "path": "story.md"}"""
  let pEmit = compileEmission(emission, "write a story")
  run.add(Check(name: "compileEmission: builds steps in order, drops prose",
                passed: pEmit.steps.len == 4 and
                        pEmit.steps[0].kind == skExtract and
                        pEmit.steps[0].source == "memory" and
                        pEmit.steps[1].kind == skGenerate and
                        pEmit.steps[1].skill == "output:story" and
                        pEmit.steps[2].kind == skReport and
                        pEmit.steps[3].kind == skWrite and
                        pEmit.steps[3].path == "story.md",
                detail: "steps=" & $pEmit.steps.len))
  run.add(Check(name: "compileEmission: bare JSON step form compiles",
                passed: pEmit.steps[3].kind == skWrite))
  run.add(Check(name: "compileEmission: goal is carried",
                passed: pEmit.goal == "write a story"))
  let pEmpty = compileEmission("just talking, no steps", "hi")
  run.add(Check(name: "compileEmission: prose-only emission -> empty plan",
                passed: pEmpty.steps.len == 0))

# ----------------------------------------------------------------------
# Eval 13: session plan/report/model recording (RFC 1000)
# ----------------------------------------------------------------------
proc evalSessionRecording*(run: var seq[Check]) =
  var s = newSession(".")
  let rootId = recordTurnStart(s, "write a story")
  var plan = newPlan("write a story")
  plan.addStep(generateStep("draft", "premise", "output:story"))
  plan.addStep(reportStep("done"))
  let planId = s.addPlan(planToJson(plan), rootId)
  let reportId = s.addReport("finished", "Story complete!", planId)

  run.add(Check(name: "addPlan records a plan node in history",
                passed: s.messages.len == 3 and
                        s.messages[1].role == mrAssistant and
                        s.messages[1].content.len == 1 and
                        s.messages[1].content[0].kind == ckPlan))
  run.add(Check(name: "addReport records a report with kind",
                passed: s.messages[2].content[0].kind == ckReport and
                        s.messages[2].content[0].reportKind == "finished" and
                        s.messages[2].content[0].text == "Story complete!"))
  run.add(Check(name: "plan and report chain by parentId",
                passed: s.messages[1].parentId == rootId and
                        s.messages[2].parentId == planId))

  let path = getTempDir() / "nimo_session_rec_test.jsonl"
  s.saveSession(path)
  if fileExists(path):
    var planLines = 0
    var reportLines = 0
    for line in path.lines:
      let trimmed = line.strip()
      if trimmed.len == 0: continue
      try:
        let j = parseJson(trimmed)
        if j.hasKey("content"):
          for p in j["content"]:
            if p.hasKey("type"):
              if p["type"].str == "plan": inc planLines
              elif p["type"].str == "report": inc reportLines
      except JsonParsingError: discard
    run.add(Check(name: "saveSession persists plan nodes",
                  passed: planLines > 0, detail: "plan=" & $planLines))
    run.add(Check(name: "saveSession persists report nodes",
                  passed: reportLines > 0, detail: "report=" & $reportLines))
    removeFile(path)

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
  evalOrchestrator(run)
  evalEmission(run)
  evalSessionRecording(run)

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
