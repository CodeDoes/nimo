## NIMO Eval Harness
## Tests the harness loop deterministically with a scripted generator (no real model needed).
## Covers three dimensions from RFC 9300-eval:
##   1. Tool calling   - does the loop detect, dispatch, and feed back tool results?
##   2. Loop termination - does it stop on a final text answer / hit max-iteration guard?
##   3. Session logging - is the JSONL message tree (user -> tool_call -> tool_result -> text) well-formed?

import std/[strutils, os, times, json]
import ./session_manager, ./pipeline, ./harness

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
# Runner
# ----------------------------------------------------------------------
proc runAllEvals*(): int =
  var run: seq[Check]
  evalToolCalling(run)
  evalLoopTermination(run)
  evalSessionLogging(run)

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
