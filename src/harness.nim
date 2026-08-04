## NIMO Harness Core Loop
## user -> generate -> tool_call -> execute -> tool_result -> generate -> ... -> final text
## Emulates the pi agent loop: think -> text/tool_call, dispatch, feed result back.

import std/[strutils, os, osproc, strformat, times, json, terminal]
import ./session_manager, ./pipeline, ./config, ./cli, ./gpu, ./bootstrap, ./rwkv/quant/cache, ./rwkv/state/cache, ./rwkv, ./rwkv/backend/cpu/cpu_backend, ./rwkv/backend/cuda/cuda_backend, ./rwkv/backend/vulkan/vulkan_backend

const
  MaxToolIterations* = 8

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
    # line is relative to `start`, so the marker sits at index 0 of the line.
    # (Using an absolute offset here crashed on second/truncated [tool] lines.)
    let nameStart = "[tool]".len
    if line.len > nameStart:
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

## ---- Core loop (composed primitives; unit-tested directly) ----
proc recordTurnStart*(s: var Session, userMsg: string): string =
  ## Records the user message that starts a turn; returns the root parentId
  ## for the history chain.
  return s.addText(userMsg, "", isThinking = false)

proc parseReply*(reply: string): seq[ToolCall] =
  ## Parses the model reply for tool calls (the 3 forms). This is a step toward
  ## the planner-emission parser (RFC 1100): the same parse compiles `[step]`
  ## lines into plan steps.
  return parseToolCalls(reply)

proc runCalls*(s: var Session, calls: seq[ToolCall], curParent: string): (string, string) =
  ## Executes each parsed call against the session's registered tools, records
  ## the tool_call + tool_result messages in the history, and returns:
  ## (feedbackText, lastParentId) — the feedback feeds the next context.
  var feedBack = ""
  var lastParent = curParent
  for call in calls:
    let toolCallId = s.addToolCall(call.name, call.args, lastParent)
    let toolResult = s.executeTool(toolCallId, call.name, call.args)
    discard s.addToolResult(toolCallId, toolResult, isError = false, parentId = toolCallId)
    feedBack.add("[tool_result for " & call.name & "]\n" & toolResult & "\n\n")
    lastParent = toolCallId
  return (feedBack, lastParent)

proc buildNextContext*(reply: string, feedBack: string): string =
  ## Strips tool markers from the reply, keeps natural text, appends the tool
  ## results and a directive to answer. Returns the next generation prompt.
  let natural = stripToolCallText(reply)
  result = if natural.len > 0: natural & "\n\n" else: ""
  result.add(feedBack & "Now answer the user's question with natural text.")

proc runHarnessTurn*(s: var Session, userMsg: string,
                     generate: GenerateFn = nil,
                     maxIterations: int = MaxToolIterations,
                     maxTokens: int = 200): HarnessTurn =
  ## Runs one full user turn through the harness loop, composing the primitives
  ## above: recordTurnStart -> generate -> parseReply -> runCalls ->
  ## buildNextContext. `generate` is the model-generation seam (injected, not
  ## stored on the session): nil = use the session's real model; a fn = mock.
  result.userInput = userMsg

  let parentId = recordTurnStart(s, userMsg)
  var context: string = buildUserPrompt(userMsg)
  var curParent = parentId

  for i in 1 .. maxIterations:
    result.iterations = i
    let reply = s.generateTurn(context, generate, DefaultTemp, DefaultTopP, maxTokens)
    result.generated = reply

    let calls = parseReply(reply)
    if calls.len == 0:
      # No tool calls -> final text answer
      result.finalText = reply
      discard s.addText(reply, curParent)
      return

    result.toolCalls.add(calls)
    let (feedBack, lastParent) = runCalls(s, calls, curParent)
    curParent = lastParent
    context = buildNextContext(reply, feedBack)

  result.aborted = true
  return

## ---- CLI entry ----
proc runHarnessCli*(cfg: NimoConfig, cwd: string = ".") =
  echo "nimo harness — user -> pipeline -> tool call -> answer"
  echo "Config file: " & DefaultConfigFile
  echo "Type /quit to exit, /save <file> to save session."
  echo ""

  # One canonical bootstrap (bind backend -> GPU policy -> quant cache -> load).
  let bs = bootstrapSession(cfg, cwd)
  for line in bs.lines:
    echo line
  if not bs.ok:
    return
  var s = bs.session

  # Single-shot smoke/benchmark mode (NIMO_SMOKE=1): load the model once,
  # generate a short reply, print a PASS line, exit. No agent loop, no system
  # prompt — this is the backend verification path scripts/smoke_test.sh uses.
  if getEnv("NIMO_SMOKE") == "1":
    let smokePrompt = block:
      let p = getEnv("NIMO_SMOKE_PROMPT")
      if p.len > 0: p else: "Say OK."
    let smokeTokens = block:
      let t = getEnv("NIMO_MAX_TOKENS")
      if t.len > 0: parseInt(t) else: cfg.maxTokens
    let t0 = cpuTime()
    let reply = s.generateTurn(smokePrompt, bs.generate, DefaultTemp,
                               DefaultTopP, smokeTokens)
    echo "[smoke] prompt: " & smokePrompt
    echo "[smoke] reply: " & reply
    echo "[smoke] " & (cpuTime() - t0).formatFloat(ffDecimal, 3) & "s"
    quit(0)

  s.registerTool("run_pipeline", proc(args: string): string =
    var sess = s
    return pipelineTool(sess, args, bs.generate))

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
    let turn = runHarnessTurn(s, line, maxTokens = cfg.maxTokens)
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

## ---- CLI entry point (main) ----
proc main() =
  # The harness owns ONLY its own arg parse + bootstrapSession + run loop (the
  # engine chat for this session), per Phase 0 item 4. It no longer re-dispatches
  # generate/bake via execCmd — those are separate binaries with their own
  # args + bootstrap.
  var cfg = loadConfig()
  if paramCount() > 1: cfg.modelPath = paramStr(2)
  if paramCount() > 2: cfg.vocabPath = paramStr(3)
  let cwd = getCurrentDir()
  runHarnessCli(cfg, cwd)

when isMainModule:
  main()
