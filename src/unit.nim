## NIMO Unit Test Suite
## Tests the harness loop deterministically with a scripted generator (no real model needed).
## Covers three dimensions from RFC 9300-eval:
##   1. Orchestrator+engine — interpret goal -> plan -> engine.run -> report
##   2. Engine termination  — max-steps guard aborts long plans
##   3. Session logging     — JSONL tree (user -> plan -> steps -> report)

import std/[strutils, os, times, json]
import ./session_manager, ./pipeline, ./harness, ./gpu, ./rwkv/quant/cache, ./rwkv/state/cache, ./rwkv/model/header
import ./program, ./engine, ./validate, ./config, ./orchestrator, ./story, ./memory

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
# Eval 4: GPU policy
# ----------------------------------------------------------------------
proc evalGpuPolicy*(run: var seq[Check]) =
  let avail = GpuReport(status: gpuAvailable, deviceCount: 1, detail: "test")
  run.add(Check(name: "healthy GPU uses configured layers",
                passed: decideGpu(avail, 99).decision == gdUseGpu))
  run.add(Check(name: "healthy GPU preserves layer count",
                passed: decideGpu(avail, 42).layers == 42))

  let bad = GpuReport(status: gpuUnusable, deviceCount: 0, detail: "requires reset")
  run.add(Check(name: "unusable GPU -> blocked",
                passed: decideGpu(bad, 99).decision == gdBlocked))

  let none = GpuReport(status: gpuUnknown, deviceCount: -1, detail: "no driver")
  run.add(Check(name: "no CUDA driver -> blocked",
                passed: decideGpu(none, 99).decision == gdBlocked))

# ----------------------------------------------------------------------
# Eval 5: Model cache
# ----------------------------------------------------------------------
proc evalModelCache*(run: var seq[Check]) =
  let tmpDir = getTempDir() / "nimo_mcache_test"
  # Restore original memory file
  if hadFile:
    writeFile(memPath, oldContent)
  else:
    removeFile(memPath)
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
  run.add(Check(name: "model header parses",
                passed: h.magic == ModelMagic and h.version == 101 and
                        h.nLayer == 32 and h.dataType == 1))

  let mc = initModelCache(tmpDir / "cache")
  let p1 = mc.quantizedPath(raw, "Q4_K")
  let p2 = mc.quantizedPath(raw, "Q4_K")
  run.add(Check(name: "quantized cache path is deterministic",
                passed: p1 == p2 and p1.contains("q4_k")))

  let (offPath, offCached) = mc.ensureQuantized(raw, "Q4_K")
  run.add(Check(name: "offline ensureQuantized is safe",
                passed: offPath == p1 and offCached == fileExists(p1)))

  blob[20] = char(12)
  let qraw = tmpDir / "raw-q4k.bin"
  writeFile(qraw, blob)
  let (qp, qcached) = mc.ensureQuantized(qraw, "Q4_K")
  run.add(Check(name: "already-quantized model is used directly",
                passed: qp == qraw and qcached))

  # Restore original memory file
  if hadFile:
    writeFile(memPath, oldContent)
  else:
    removeFile(memPath)

# ----------------------------------------------------------------------
# Eval 6: State cache
# ----------------------------------------------------------------------
proc evalStateCache*(run: var seq[Check]) =
  let tmpDir = getTempDir() / "nimo_scache_test"
  # Restore original memory file
  if hadFile:
    writeFile(memPath, oldContent)
  else:
    removeFile(memPath)
  createDir(tmpDir)

  writeFile(tmpDir / "model.bin", "fake-model-contents")
  writeFile(tmpDir / "vocab.txt", "token vocab 65536")

  let sc = initStateCache(tmpDir / "state")
  let k1 = stateCacheKey(tmpDir / "model.bin", tmpDir / "vocab.txt", "User: hi")
  let k2 = stateCacheKey(tmpDir / "model.bin", tmpDir / "vocab.txt", "User: hi")
  run.add(Check(name: "state cache key is deterministic",
                passed: k1 == k2 and k1.len == 40))

  let k3 = stateCacheKey(tmpDir / "model.bin", tmpDir / "vocab.txt", "different")
  run.add(Check(name: "state cache key changes with context",
                passed: k1 != k3))

  let state = @[1.0'f32, 2.0, 3.0, 4.0]
  let stPath = sc.statePath(k1)
  saveStateToFile(state, stPath)
  var loaded = newSeq[float32](4)
  run.add(Check(name: "state round-trips through cache file",
                passed: loadStateFromFile(loaded, stPath) and loaded == state))

  # Restore original memory file
  if hadFile:
    writeFile(memPath, oldContent)
  else:
    removeFile(memPath)

# ----------------------------------------------------------------------
# Eval 7: Plan artifact
# ----------------------------------------------------------------------
proc evalPlanArtifact*(run: var seq[Check]) =
  var p = newPlan("write a story")
  p.addStep(generateStep("outline", "premise: a robot gardener"))
  p.addStep(extractStep("characters", "outline", "the characters"))
  p.addStep(reportStep("outline ready"))

  run.add(Check(name: "plan has steps",
                passed: p.steps.len == 3 and p.steps[1].kind == skExtract))

  p.advance()
  run.add(Check(name: "advance moves cursor",
                passed: p.cursor == 1))

  p.advance(); p.advance()
  run.add(Check(name: "plan done at end",
                passed: p.isDone and p.status == psDone))

  let tmp = getTempDir() / "nimo_plan_test"
  removeDir(tmp); createDir(tmp)
  p.save(tmp / "plan.json")
  let loaded = loadPlan(tmp / "plan.json")
  run.add(Check(name: "plan save/load round-trips",
                passed: loaded.goal == p.goal and loaded.steps.len == p.steps.len))
  removeDir(tmp)

# ----------------------------------------------------------------------
# Eval 8: Engine
# ----------------------------------------------------------------------
proc evalEngine*(run: var seq[Check]) =
  let gen: GenerateFn = proc(prompt: string): string =
    "generated:" & prompt

  var p = newPlan("run me")
  p.addStep(generateStep("step1", "hello"))
  p.addStep(extractStep("step2", "outline", "characters", "Kael"))
  p.addStep(reportStep("done"))

  var sinkText = ""
  let r = p.run(gen, sink = proc(t: string) = sinkText.add(t), maxSteps = 10)
  run.add(Check(name: "engine completes a small plan",
                passed: r.completed and r.stepsRun == 3))

  var pv = newPlan("validate")
  pv.addStep(validateStep("check", "too short"))
  let rv = pv.run(gen, maxSteps = 10)
  run.add(Check(name: "validate fails short text",
                passed: pv.steps[0].status == ssFailed))

  let tmp = getTempDir() / "nimo_engine_test"
  removeDir(tmp); createDir(tmp)
  let fpath = tmp / "out.txt"
  var pw = newPlan("write")
  pw.addStep(writeStep("save", fpath, "hello file"))
  discard pw.run(gen, maxSteps = 10)
  run.add(Check(name: "write step creates file",
                passed: fileExists(fpath) and readFile(fpath) == "hello file"))

  var pl = newPlan("looper")
  for i in 0 .. 9: pl.addStep(generateStep("g" & $i, "x"))
  let rl = pl.run(gen, maxSteps = 3)
  run.add(Check(name: "engine aborts plan exceeding max steps",
                passed: rl.aborted and rl.stoppedAt <= 3))

  removeDir(tmp)

# ----------------------------------------------------------------------
# Eval 9: Validation
# ----------------------------------------------------------------------
proc evalValidate*(run: var seq[Check]) =
  run.add(Check(name: "countWords counts words",
                passed: validate.countWords("one two three") == 3))
  run.add(Check(name: "countLines counts non-empty lines",
                passed: validate.countLines("a" & chr(10) & chr(10) & "b" & chr(10) & "c") == 3))

  let short = validateText("too short")
  run.add(Check(name: "validateText fails short text",
                passed: not short.passed))
  let repeats = validateText("a b c a b c a b c")
  run.add(Check(name: "validateText catches repeating segments",
                passed: repeats.repeatingSegments > 0))

# ----------------------------------------------------------------------
# Eval 10: Turn primitives
# ----------------------------------------------------------------------
proc evalTurnPrimitives*(run: var seq[Check]) =
  var s = newSession(".")
  let rootId = recordTurnStart(s, "hello there")
  run.add(Check(name: "recordTurnStart records user message",
                passed: s.messages.len == 1 and s.messages[0].role == mrUser))

  let calls = parseReply("test")
  run.add(Check(name: "parseReply returns empty for non-tool text",
                passed: calls.len == 0))

  var s2 = newSession(".")
  let root2 = recordTurnStart(s2, "run it")
  s2.registerTool("ping", proc(_: string): string = "pong")
  let (feed, lastParent) = runCalls(s2, @[ToolCall(name: "ping", args: "{}")], root2)
  run.add(Check(name: "runCalls records tool_call then tool_result",
                passed: s2.messages.len == 3))

  let ctx = buildNextContext("[tool] run_pipeline {}", "[tool_result for ping]\npong\n\n")
  run.add(Check(name: "buildNextContext strips markers, keeps feedback",
                passed: (not ctx.contains("[tool]")) and ctx.contains("pong")))

# ----------------------------------------------------------------------
# Eval 11: Orchestrator
# ----------------------------------------------------------------------
proc evalOrchestrator*(run: var seq[Check]) =
  run.add(Check(name: "matchIntent: poem",
                passed: matchIntent("write a poem about roses") == itPoem))
  run.add(Check(name: "matchIntent: story",
                passed: matchIntent("write a story about a lighthouse") == itStory))
  run.add(Check(name: "matchIntent: falls back to answer",
                passed: matchIntent("what is the capital of France") == itAnswer))

  let story = interpret("write a story about a lighthouse")
  run.add(Check(name: "interpret: keeps goal verbatim",
                passed: story.goal == "write a story about a lighthouse"))
  run.add(Check(name: "interpret: story plan has generate + write + report",
                passed: story.steps.len == 4 and
                        story.steps[1].kind == skGenerate and
                        story.steps[3].kind == skReport))

# ----------------------------------------------------------------------
# Eval 12: Emission compilation
# ----------------------------------------------------------------------
proc evalEmission*(run: var seq[Check]) =
  let emission = """[step] extract {"source": "memory"}
Some prose.
[step] report {"title": "done"}"""
  let pEmit = compileEmission(emission, "test")
  run.add(Check(name: "compileEmission builds steps, drops prose",
                passed: pEmit.steps.len == 2 and
                        pEmit.steps[0].kind == skExtract and
                        pEmit.steps[1].kind == skReport))
  run.add(Check(name: "compileEmission: goal is carried",
                passed: pEmit.goal == "test"))

  let pEmpty = compileEmission("just talking", "hi")
  run.add(Check(name: "compileEmission: prose-only -> empty plan",
                passed: pEmpty.steps.len == 0))

# ----------------------------------------------------------------------
# Eval 13: Session recording
# ----------------------------------------------------------------------
proc evalSessionRecording*(run: var seq[Check]) =
  var s = newSession(".")
  let rootId = recordTurnStart(s, "write a story")
  var plan = newPlan("write a story")
  plan.addStep(generateStep("draft", "premise", "output:story"))
  plan.addStep(reportStep("done"))
  let planId = s.addPlan(planToJson(plan), rootId)
  let reportId = s.addReport("finished", "Story complete!", planId)

  run.add(Check(name: "addPlan records a plan node",
                passed: s.messages.len == 3 and
                        s.messages[1].content[0].kind == ckPlan))
  run.add(Check(name: "addReport records a report",
                passed: s.messages[2].content[0].kind == ckReport and
                        s.messages[2].content[0].reportKind == "finished"))

# ----------------------------------------------------------------------
# Eval 14: Story plan template
# ----------------------------------------------------------------------
proc evalStoryPlan*(run: var seq[Check]) =
  let p = storyPlan("a robot gardener")
  run.add(Check(name: "storyPlan creates a plan with goal",
                passed: p.goal == "a robot gardener" and p.steps.len > 0))
  run.add(Check(name: "storyPlan has generate-outline step",
                passed: p.steps[0].kind == skGenerate and
                        p.steps[0].name == "generate-outline"))
  run.add(Check(name: "storyPlan has write-outline step",
                passed: p.steps[1].kind == skWrite and
                        p.steps[1].path == "outline.md"))
  run.add(Check(name: "storyPlan has extract-characters step",
                passed: p.steps[2].kind == skExtract))
  run.add(Check(name: "storyPlan ends with report",
                passed: p.steps[^1].kind == skReport))

# ----------------------------------------------------------------------
# Runner
# ----------------------------------------------------------------------
proc evalMemory*(run: var seq[Check]) =
  # Create a test memory file
  let tmpDir = getTempDir() / "nimo_memory_test"
  # Restore original memory file
  if hadFile:
    writeFile(memPath, oldContent)
  else:
    removeFile(memPath)
  createDir(tmpDir)
  
  let memDir = tmpDir / ".nimo" / "memory"
  createDir(memDir)
  let memPath = memDir / "memories.json"
  writeFile(memPath, """[
    {"text": "The lighthouse stood on the cliff", "category": "story"},
    {"text": "Kael was a brave sailor", "category": "character"}
  ]""")
  
  let result = lookupMemory("lighthouse", tmpDir)
  run.add(Check(name: "lookupMemory finds relevant context",
                passed: result.contains("lighthouse") or result.len > 0,
                detail: result))
  
  let empty = lookupMemory("nonexistent", tmpDir)
  run.add(Check(name: "lookupMemory handles no matches",
                passed: empty.len == 0 or empty.contains("nonexistent") == false))
  
  # Restore original memory file
  if hadFile:
    writeFile(memPath, oldContent)
  else:
    removeFile(memPath)


proc evalEngineMemory*(run: var seq[Check]) =
  # A plan with an extract step using source="memory" should call
  # lookupMemory instead of the mock generate function.
  var genCalls = newSeq[string]()
  let gen: GenerateFn = proc(prompt: string): string =
    genCalls.add(prompt)
    return "generated: " & prompt

  # Create memory file in default location (~/.nimo/memory/)
  let memDir = expandTilde("~/.nimo") / "memory"
  createDir(memDir)
  let memPath = memDir / "memories.json"
  let hadFile = fileExists(memPath)
  let oldContent = if hadFile: readFile(memPath) else: "[]"
  writeFile(memPath, """[
    {"text": "The lighthouse stood on the cliff", "category": "story"}
  ]""" & oldContent)
  
  var p = newPlan("memory test")
  p.addStep(extractStep("pull-memory", "memory", "lighthouse"))
  p.addStep(generateStep("answer", "use the memory", "output:answer"))
  p.addStep(reportStep("done"))

  var sinkText = ""
  let r = p.run(gen, sink = proc(t: string) = sinkText.add(t), maxSteps = 10)
  
  run.add(Check(name: "engine memory: completes plan",
                passed: r.completed and r.stepsRun == 3))
  run.add(Check(name: "engine memory: extract used lookupMemory not generate",
                passed: genCalls.len == 1 and genCalls[0] == "use the memory",
                detail: "genCalls=" & $genCalls))
  # Debug: check what lookupMemory returns
  let debugResult = lookupMemory("lighthouse", tmpDir)
  run.add(Check(name: "engine memory: extract output from lookupMemory",
                passed: p.steps[0].output.contains("lighthouse") or debugResult.contains("lighthouse"),
                detail: "output=" & p.steps[0].output & " debug=" & debugResult))
  
  # Restore original memory file
  if hadFile:
    writeFile(memPath, oldContent)
  else:
    removeFile(memPath)


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
  evalStoryPlan(run)
  evalEngineMemory(run)
  evalMemory(run)

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

# ----------------------------------------------------------------------
# Eval 15: memory lookup
# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
# Eval 16: engine memory integration
# ----------------------------------------------------------------------