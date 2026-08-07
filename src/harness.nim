## NIMO Harness Core Loop
## user -> generate -> tool_call -> execute -> tool_result -> generate -> ... -> final text
## Emulates the pi agent loop: think -> text/tool_call, dispatch, feed result back.

import std/[strutils, os, times, json, terminal]
import ./session_manager, ./pipeline, ./config, ./bootstrap, ./orchestrator, ./program, ./engine

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
      if j.kind == JObject and "name" in j and "arguments" in j:
        result.add(ToolCall(
          name: j["name"].str,
          args: $(j["arguments"]),
          raw: text[start .. endPos + "</tool_call>".len - 1]
        ))
    except CatchableError:
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
      if j.kind == JObject:
        var name = ""
        if "name" in j and j["name"].kind == JString:
          name = j["name"].str
        elif "tool" in j and j["tool"].kind == JString:
          name = j["tool"].str
        elif "arguments" in j and ("prompt" in j["arguments"] or "intent" in j["arguments"]):
          name = "run_pipeline"
        if name.len > 0 and "arguments" in j:
          result.add(ToolCall(name: name, args: $(j["arguments"]), raw: trimmed))
    except CatchableError:
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
        if j.kind == JObject:
          if ("name" in j and "arguments" in j) or
             ("tool" in j and "arguments" in j) or
             ("arguments" in j and ("prompt" in j["arguments"] or "intent" in j["arguments"])):
            continue
      except CatchableError:
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

proc extractTargetFile*(userMsg: string): string =
  ## Deterministically extracts a target file path from a prompt like
  ## "write a file called NOTES.md ..." / "save to docs/x.txt" / "create X.md".
  ## Returns "" if no filename is mentioned (caller then just answers).
  let s = userMsg.toLowerAscii()
  let ws = getCurrentDir()

  proc derive(p: string): string =
    ## Cleans a raw candidate: strips quotes, trailing punctuation + whitespace.
    var t = p.strip()
    if t.len >= 2 and (t[0] == '\"' or t[0] == '\''):
      t = t[1 .. ^1]
    if t.len >= 1 and (t[^1] == '\"' or t[^1] == '\''):
      t = t[0 ..< ^1]
    # Stop at a trailing word boundary filler like " with 20 things"
    var cut = t.len
    for w in [" with ", " containing ", " about ", " and "]:
      let ix = t.toLowerAscii().find(w)
      if ix > 0 and ix < cut:
        cut = ix
    t = t[0 ..< cut].strip()
    # Only accept something that looks like a file (has text, maybe an ext)
    if t.len == 0: return ""
    # reject if it contains spaces (not a bare filename) unless it's the last clause
    if t.contains(" ") and t.find(".") < 0:
      return ""
    if t[^1] == '.': t = t[0 .. ^2]
    return t

  for pat in ["called \"", "called\"", "write a file called ",
              "file called ", "save to ", "save as ", "create a file ",
              "create ", "write "]:
    let ix = s.find(pat)
    if ix >= 0:
      let rest = userMsg[ix + pat.len .. ^1]
      # take the first whitespace-bounded / quoted chunk that looks filesy
      let cand = derive(rest)
      if cand.len > 0:
        # absolute or relative under the workspace
        if isAbsolute(cand): return cand
        return ws / cand
  return ""

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
                     maxTokens: int = 200,
                     sink: TokenSink = nil,
                     generateStream: GenerateStreamFn = nil): HarnessTurn =
  ## Runs one full user turn through the orchestrator + engine:
  ## recordTurnStart -> interpret -> addPlan -> engine.run -> addReport.
  ## `generate` is the model-generation seam (injected, not stored on the
  ## session): nil = use the session's real model; a fn = mock. `generateStream`
  ## streams tokens live (real-model path); build it at the call site where the
  ## session is a local var (a closure cannot capture a `var Session` param).
  result.userInput = userMsg

  let rootId = recordTurnStart(s, userMsg)

  # Compile the goal into a plan (orchestrator seam).
  var plan = interpret(userMsg)
  let planId = s.addPlan(planToJson(plan), rootId)

  # Run the plan through the engine; collect emitted text.
  var sinkText = ""
  let collector: TokenSink = proc(t: string) =
    sinkText.add(t)
    if sink != nil:
      sink(t)
  let r = plan.run(generate, sink = collector, interrupt = nil,
                   maxSteps = maxIterations, generateStream = generateStream)
  result.iterations = r.stepsRun
  result.aborted = r.aborted
  result.generated = sinkText

  # Persist generated content and a finished report in the message tree. The
  # plan node remains the parent so a saved session is user -> plan -> output
  # -> report, rather than a transient terminal-only trace.
  var generatedParts: seq[string]
  for step in plan.steps:
    if step.kind == skGenerate and step.output.len > 0:
      generatedParts.add(step.output)
  result.finalText = generatedParts.join("\n\n").strip()
  if result.finalText.len == 0:
    result.finalText = sinkText.strip()
  if result.finalText.len > 0:
    let outputId = s.addText(result.finalText, planId)
    discard s.addReport("finished", "Completed: " & plan.goal, outputId)

## ---- CLI entry ----
proc saveOptsSession*(s: Session, path: string) =
  ## Saves a session file and echoes where it went (used for -s).
  if path.len == 0: return
  s.saveSession(path)
  echo "[session] saved " & path

type
  HarnessOpts* = object
    smoke*: bool           # single-shot smoke/benchmark (no agent loop)
    prompt*: string        # one-shot prompt: run ONE user turn then exit
    oneShot*: bool         # true when -p given: user -> agent-cycle -> exit
    sessionFile*: string   # -s: JSONL session file to load + append to
    workspace*: string     # -w: workspace dir (chdir before running)
    maxTokens*: int        # smoke token cap

proc runHarnessCli*(cfg: NimoConfig, cwd: string = ".",
                    opts: HarnessOpts = HarnessOpts()) =
  echo "nimo harness — user -> pipeline -> tool call -> answer"
  echo "Config file: " & DefaultConfigFile

  # -w workspace: chdir first so the config + caches resolve relative to it.
  var workdir = cwd
  if opts.workspace.len > 0:
    if not dirExists(opts.workspace):
      createDir(opts.workspace)
    workdir = opts.workspace
    setCurrentDir(workdir)
    echo "[workspace] " & workdir

  # -s: resume an existing session file if present.
  var resumed = false
  if opts.sessionFile.len > 0 and fileExists(opts.sessionFile):
    let probe = newSession(workdir)
    if probe.loadSession(opts.sessionFile):
      resumed = true
    # probe was just a reader probe; we'll rebuild the real session below.

  if opts.oneShot:
    echo "One-shot (" & (if resumed: "resumed session" else: "fresh session") &
         "): " & opts.prompt
  else:
    echo "Type /quit to exit, /save <file> to save session."
  echo ""

  # One canonical bootstrap (bind backend -> GPU policy -> quant cache -> load).
  let bs = bootstrapSession(cfg, workdir)
  for line in bs.lines:
    echo line
  if not bs.ok:
    return
  var s = bs.session

  # If a session file was found earlier, load its message history onto the
  # fresh model-backed session so multi-turn context resumes.
  if resumed:
    discard s.loadSession(opts.sessionFile)

  # Single-shot smoke/benchmark mode (--smoke flag): load the model once,
  # generate a short reply, print a PASS line, exit. No agent loop, no system
  # prompt — the backend verification path scripts/smoke_test.sh uses. An
  # explicit flag, not an env precedence ladder.
  if opts.smoke:
    let prompt = if opts.prompt.len > 0: opts.prompt else: "Say OK."
    let maxTokens = if opts.maxTokens > 0: opts.maxTokens else: cfg.maxTokens
    let t0 = cpuTime()
    let reply = s.generateTurn(prompt, bs.generate, DefaultTemp, DefaultTopP, maxTokens)
    echo "[smoke] prompt: " & prompt
    echo "[smoke] reply: " & reply
    echo "[smoke] " & (cpuTime() - t0).formatFloat(ffDecimal, 3) & "s"
    quit(0)

  s.registerTool("run_pipeline", proc(args: string): string =
    var sess = s
    return pipelineTool(sess, args, bs.generate))

  # One-shot mode (-p): run exactly one user turn (user -> agent cycle -> final
  # answer), stream the output + tool calls to stdout, save the session, exit.
  if opts.oneShot:
    let t0 = cpuTime()
    var stream: GenerateStreamFn = nil
    if bs.generate == nil:
      stream = proc(prompt: string, tokenSink: TokenSink): string =
        s.generateTurnStream(prompt, tokenSink, nil, DefaultTemp, DefaultTopP, cfg.maxTokens)
    let turn = runHarnessTurn(s, opts.prompt, generate = bs.generate,
      maxTokens = cfg.maxTokens,
      sink = proc(t: string) =
        stdout.write(t)
        stdout.flushFile(),
      generateStream = stream)
    let elapsed = cpuTime() - t0

    echo ""
    if turn.finalText.len == 0:
      echo "[nimo] No final answer produced."

    # Deterministic file write: if the user asked for a file ("write a file
    # called X", "save to X", "create X"), write the turn's output to that
    # path under the workspace — the coherence lives in the program, not in
    # the model's willingness to emit a [tool] call.
    let target = extractTargetFile(opts.prompt)
    if target.len > 0 and turn.finalText.len > 0:
      let absTarget = if isAbsolute(target): target else: getCurrentDir() / target
      let d = parentDir(absTarget)
      if d.len > 0 and d != "." and not dirExists(d):
        createDir(d)
      writeFile(absTarget, turn.finalText)
      echo "[file] wrote " & $turn.finalText.len & " bytes -> " & absTarget

    if opts.sessionFile.len > 0:
      saveOptsSession(s, opts.sessionFile)
    var stats = "  (" & $turn.iterations & " steps"
    if turn.aborted:
      stats.add(", aborted")
    stats.add(", " & elapsed.formatFloat(ffDecimal, 1) & "s)")
    setForegroundColor(fgYellow, true)
    echo stats
    setForegroundColor(fgDefault)
    quit(0)

  while true:
    stdout.write("\n> ")
    stdout.flushFile()
    var line = ""
    try:
      line = stdin.readLine()
    except EOFError:
      break
    if line.len == 0: continue
    if line == "/quit":
      if opts.sessionFile.len > 0:
        saveOptsSession(s, opts.sessionFile)
      break
    if line.startsWith("/save"):
      let parts = line.splitWhitespace()
      if parts.len > 1:
        s.saveSession(parts[1])
        echo "Session saved to " & parts[1]
      else:
        echo "Usage: /save <file>"
      continue

    let t0 = cpuTime()
    # Real-model path: stream decoded tokens straight to the terminal. The
    # closure captures the local `s` (safe) — it cannot capture the var param
    # inside runHarnessTurn, so we build it here and pass it down.
    var stream: GenerateStreamFn = nil
    if bs.generate == nil:
      stream = proc(prompt: string, tokenSink: TokenSink): string =
        s.generateTurnStream(prompt, tokenSink, nil, DefaultTemp, DefaultTopP, cfg.maxTokens)
    let turn = runHarnessTurn(s, line, generate = bs.generate,
      maxTokens = cfg.maxTokens,
      sink = proc(t: string) =
        stdout.write(t)
        stdout.flushFile(),
      generateStream = stream)
    let elapsed = cpuTime() - t0

    echo ""
    if turn.finalText.len == 0:
      echo "[nimo] No final answer produced."

    var stats = "  (" & $turn.iterations & " steps"
    if turn.aborted:
      stats.add(", aborted")
    stats.add(", " & elapsed.formatFloat(ffDecimal, 1) & "s)")
    setForegroundColor(fgYellow, true)
    echo stats
    setForegroundColor(fgDefault)

## ---- CLI entry point (main) ----
proc main() =
  # The harness owns ONLY its own arg parse + bootstrapSession + run loop (the
  # engine chat for this session), per Phase 0 item 4. It no longer re-dispatches
  # generate/bake via execCmd — those are separate binaries with their own
  # args + bootstrap. Backend choice is an explicit --backend flag (like
  # generate.nim), never an env precedence chain.
  var cfg = loadConfig()
  var opts = HarnessOpts()
  var positional: seq[string]
  var i = 1
  while i <= paramCount():
    let a = paramStr(i)
    if a == "--backend" and i < paramCount():
      inc i
      try:
        cfg.backend = parseBackendKind(paramStr(i))
        cfg.backendSet = true
      except ValueError:
        echo "Error: unknown backend '" & paramStr(i) & "' (expected cuda|vulkan)"
        quit(1)
    elif a == "--model" and i < paramCount():
      inc i; cfg.modelPath = paramStr(i)
    elif a == "--vocab" and i < paramCount():
      inc i; cfg.vocabPath = paramStr(i)
    elif a == "--smoke":
      opts.smoke = true
    elif a == "-p" and i < paramCount():
      inc i; opts.prompt = paramStr(i); opts.oneShot = true
    elif a == "-s" and i < paramCount():
      inc i; opts.sessionFile = paramStr(i)
    elif a == "-w" and i < paramCount():
      inc i; opts.workspace = paramStr(i)
    elif a == "--prompt" and i < paramCount():
      inc i; opts.prompt = paramStr(i); opts.oneShot = true
    elif a == "--script-replies" and i < paramCount():
      inc i; cfg.scriptReplies = paramStr(i)
    elif a == "--seed" and i < paramCount():
      inc i
      try: cfg.seed = parseInt(paramStr(i))
      except ValueError:
        echo "Error: invalid --seed value (expected integer)"
        quit(1)
    elif a == "--max-tokens" and i < paramCount():
      inc i
      try: opts.maxTokens = parseInt(paramStr(i))
      except ValueError:
        echo "Error: invalid --max-tokens value"
        quit(1)
    elif a.startsWith("--"):
      echo "Error: unknown option '" & a & "'"
      quit(1)
    else:
      positional.add(a)
    inc i
  # No bare text may be pushed into the session. A positional arg is only ever
  # a model/vocab FILE path (legacy); anything else is almost certainly a
  # mistyped message, and silently swallowing it as a model path drops the
  # text. Initial messages must be explicit via -p/--prompt.
  if positional.len > 0 and not fileExists(positional[0]) and not dirExists(positional[0]):
    echo "Error: unrecognized positional '" & positional[0] & "'."
    echo ""
    echo "To send a message into the session, use explicitly:"
    echo "  nimo harness -p \"<message>\"   (or --prompt)"
    echo "To pick a model file:"
    echo "  nimo harness --model <path> [--vocab <path>]"
    quit(1)
  if positional.len > 0: cfg.modelPath = positional[0]
  if positional.len > 1: cfg.vocabPath = positional[1]
  runHarnessCli(cfg, getCurrentDir(), opts)

when isMainModule:
  main()
