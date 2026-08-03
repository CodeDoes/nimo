## NIMO Harness Core Loop
## user -> generate -> tool_call -> execute -> tool_result -> generate -> ... -> final text
## Emulates the pi agent loop: think -> text/tool_call, dispatch, feed result back.

import std/[strutils, os, times, json, terminal]
import ./session_manager, ./pipeline, ./config, ./cli

const
  MaxToolIterations* = 8
  HarnessDefaultModel* = "models/rwkv7-g1i-2.9b-20260729-ctx16384-f16.bin"
  HarnessDefaultVocab* = "rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt"

type
  ToolCall* = object
    name*: string
    args*: string
    raw*: string

  HarnessTurn* = object
    userInput*: string
    generated*: string
    toolCalls*: seq[ToolCall]
    finalText*: string
    iterations*: int
    aborted*: bool

## ---- Tool call parsing ----
## Model emits tool calls in one of two forms (MVP):
##   [tool] run_pipeline {"intent": "..."}
##   <tool_call>{"name":"run_pipeline","arguments":{...}}</tool_call>

proc parseToolCalls*(text: string): seq[ToolCall] =
  result = newSeq[ToolCall]()

  # Form 1: [tool] name {...json}
  var pos = 0
  while true:
    let start = text.find("[tool]", pos)
    if start < 0: break
    let lineEnd = text.find("\n", start)
    let line = if lineEnd < 0: text[start .. ^1] else: text[start ..< lineEnd]
    let nameStart = start + "[tool]".len
    let rest = line[nameStart .. ^1].strip()
    let spaceIdx = rest.find({' ', '\t'})
    if spaceIdx > 0:
      let name = rest[0 ..< spaceIdx].strip()
      let args = rest[spaceIdx .. ^1].strip()
      result.add(ToolCall(name: name, args: args, raw: line))
    pos = if lineEnd < 0: text.len else: lineEnd + 1

  # Form 2: <tool_call>...</tool_call> with JSON
  pos = 0
  while true:
    let start = text.find("<tool_call>", pos)
    if start < 0: break
    let endPos = text.find("</tool_call>", start)
    if endPos < 0: break
    let inner = text[start + "<tool_call>".len ..< endPos].strip()
    try:
      let j = parseJson(inner)
      if "name" in j and "arguments" in j:
        result.add(ToolCall(
          name: j["name"].str,
          args: $(j["arguments"]),
          raw: text[start .. endPos + "</tool_call>".len - 1]
        ))
    except JsonParsingError:
      discard
    pos = endPos + "</tool_call>".len

  # Form 3: bare JSON object line like {"name":"run_pipeline","arguments":{...}}
  # or {"tool":"run_pipeline",...} or {"arguments":{...},"prompt":...}
  for line in text.splitLines():
    let trimmed = line.strip()
    if trimmed.len < 2 or not trimmed.startsWith("{"):
      continue
    # skip lines already captured as [tool] or <tool_call>
    var already = false
    for c in result:
      if c.raw.strip() == trimmed:
        already = true
        break
    if already: continue
    try:
      let j = parseJson(trimmed)
      var name = ""
      if "name" in j and j["name"].kind == JString:
        name = j["name"].str
      elif "tool" in j and j["tool"].kind == JString:
        name = j["tool"].str
      elif "arguments" in j and ("prompt" in j["arguments"] or "intent" in j["arguments"]):
        name = "run_pipeline"
      if name.len > 0 and "arguments" in j:
        result.add(ToolCall(name: name, args: $(j["arguments"]), raw: trimmed))
    except JsonParsingError:
      discard

proc stripToolCallText*(text: string): string =
  ## Removes tool call markers, leaving only natural text.
  result = text
  # Form 2 first (multi-line safe)
  var pos = 0
  while true:
    let start = result.find("<tool_call>", pos)
    if start < 0: break
    let endPos = result.find("</tool_call>", start)
    if endPos < 0: break
    result = result[0 ..< start] & result[endPos + "</tool_call>".len .. ^1]
    pos = start
  # Form 1 (line based)
  var lines = result.splitLines()
  var keptLines: seq[string]
  for line in lines:
    let t = line.strip()
    if t.startsWith("[tool]") or t.startsWith("<tool_call>"):
      continue
    # drop bare JSON tool-call lines
    if t.startsWith("{") and t.endsWith("}"):
      try:
        let j = parseJson(t)
        if ("name" in j and "arguments" in j) or
           ("tool" in j and "arguments" in j) or
           ("arguments" in j and ("prompt" in j["arguments"] or "intent" in j["arguments"])):
          continue
      except JsonParsingError:
        discard
    keptLines.add(line)
  result = keptLines.join("\n").strip()

## ---- System prompt for tool usage ----
const HarnessSystemPrompt* = """You are a helpful assistant running inside the nimo harness.
You have access to one tool: run_pipeline. It runs a generation pipeline for you.

When the user asks you to write, generate, create, or produce content, call the tool
by outputting EXACTLY one line, nothing else around it:
[tool] run_pipeline {"intent": "what you want to write about"}

Example:
User: write me a poem about roses
Assistant: [tool] run_pipeline {"intent": "write a short poem about roses"}

After the tool result comes back, answer the user with natural text.
If no tool is needed, just answer directly in natural text."""

proc buildUserPrompt*(userMsg: string): string =
  result = HarnessSystemPrompt & "\n\nUser: " & userMsg

## ---- Core loop ----
proc runHarnessTurn*(s: var Session, userMsg: string, maxIterations: int = MaxToolIterations): HarnessTurn =
  ## Runs one full user turn through the harness loop.
  result.userInput = userMsg

  let parentId = s.addText(userMsg, "", isThinking = false)

  var context: string = buildUserPrompt(userMsg)
  var curParent = parentId

  for i in 1 .. maxIterations:
    result.iterations = i
    let reply = s.generateTurn(context, DefaultTemp, DefaultTopP)
    result.generated = reply

    let calls = parseToolCalls(reply)
    if calls.len == 0:
      # No tool calls -> final text answer
      result.finalText = reply
      discard s.addText(reply, curParent)
      return

    result.toolCalls.add(calls)
    var feedBack = ""
    for call in calls:
      let toolCallId = s.addToolCall(call.name, call.args, curParent)
      let toolResult = s.executeTool(toolCallId, call.name, call.args)
      discard s.addToolResult(toolCallId, toolResult, isError = false, parentId = toolCallId)
      feedBack.add("[tool_result for " & call.name & "]\n" & toolResult & "\n\n")
      curParent = toolCallId

    # Strip tool markers, keep natural text if any, then append results
    let natural = stripToolCallText(reply)
    context = if natural.len > 0: natural & "\n\n" else: ""
    context.add(feedBack & "Now answer the user's question with natural text.")
    if context.len == 0:
      break

  result.aborted = true
  return

## ---- CLI entry ----
proc runHarnessCli*(modelPath: string, vocabPath: string, cwd: string = ".") =
  echo "nimo harness — user -> pipeline -> tool call -> answer"
  echo "Type /quit to exit, /save <file> to save session."
  echo ""

  var s = newSession(cwd)
  when not defined(harnessOffline):
    s.initModel(modelPath, vocabPath)
  else:
    echo "[nimo] offline mode: no model loaded; generation will return placeholder text"
    s.genStub = proc(userMsg: string): string = "[nimo offline] no model"
  s.registerTool("run_pipeline", proc(args: string): string =
    var sess = s
    return pipelineTool(sess, args))

  while true:
    stdout.write("\n> ")
    stdout.flushFile()
    let line = stdin.readLine()
    if line.len == 0: continue
    if line == "/quit": break
    if line.startsWith("/save"):
      let parts = line.splitWhitespace()
      if parts.len > 1:
        s.saveSession(parts[1])
        echo "Session saved to " & parts[1]
      else:
        echo "Usage: /save <file>"
      continue

    let t0 = cpuTime()
    let turn = runHarnessTurn(s, line)
    let elapsed = cpuTime() - t0

    echo ""
    if turn.finalText.len > 0:
      echo turn.finalText
    else:
      echo "[nimo] No final answer produced."

    var stats = "  (" & $turn.iterations & " iterations"
    if turn.toolCalls.len > 0:
      stats.add(", " & $turn.toolCalls.len & " tool call(s): " & turn.toolCalls[0].name)
    stats.add(", " & elapsed.formatFloat(ffDecimal, 1) & "s)")
    setForegroundColor(fgYellow, true)
    echo stats
    setForegroundColor(fgDefault)
