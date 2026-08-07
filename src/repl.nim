## repl.nim — `nimo repl` : the Unified Protocol REPL (RFC 2110)
##
## A line-driven shell whose commands are the SAME small, deterministic
## operations the chat agent composes (send/queue/steer, planner, ws, session,
## story chapter …, cuda status, state …).
##
## Invariant: every model-touching command goes through the SAME
## `bootstrapSession(cfg, cwd)` seam the chat uses, and every turn goes through
## `runHarnessTurn` — the chat's own per-turn driver. The REPL is a human
## driving the identical machinery.
##
## Offline-safe: with -d:harnessOffline model-backed commands use the stub
## generator; ws/planner/session/story-validate work with no GPU.

import std/[os, json]
import ./config, ./orchestrator, ./workspace, ./story, ./bootstrap, ./harness
import ./session_manager

when not defined(harnessOffline):
  import ./gpu

type
  ReplContext* = object
    cfg*: NimoConfig
    cwd*: string
    ws*: Workspace
    hasWs*: bool
    session*: Session
    hasSession*: bool
    bs*: BootstrapResult
    bootstrapped*: bool
    pending*: seq[string]
    sessionPath*: string

# ---------------------------------------------------------------------------
# Tokenizer — quote-aware, so `send "a man walks in"` is ONE argument.
# ---------------------------------------------------------------------------
proc tokenize(line: string): seq[string] =
  result = @[]
  var cur = ""
  var inQuote = false
  var i = 0
  while i < line.len:
    let c = line[i]
    if c == '"':
      inQuote = not inQuote
    elif c == ' ' and not inQuote:
      if cur.len > 0:
        result.add cur
        cur = ""
    else:
      cur.add c
    inc i
  if cur.len > 0: result.add cur

proc flagVal(tokens: seq[string], flag: string): string =
  for i, t in tokens:
    if t == flag and i + 1 < tokens.len: return tokens[i + 1]
  return ""

proc hasFlag(tokens: seq[string], flag: string): bool =
  flag in tokens

# ---------------------------------------------------------------------------
# One bootstrap, reused by every model command.
# ---------------------------------------------------------------------------
proc ensureModel(ctx: var ReplContext): bool =
  if ctx.bootstrapped: return true
  let bs = bootstrapSession(ctx.cfg, ctx.cwd)
  for line in bs.lines: echo line
  if not bs.ok:
    echo "[repl] model unavailable; ws / planner / session / validate still work."
    return false
  ctx.bs = bs
  ctx.session = bs.session
  ctx.hasSession = true
  ctx.bootstrapped = true
  return true

proc replTurn(ctx: var ReplContext, msg: string): bool =
  ## One agent-cycle — exactly `runHarnessTurn`, the same the chat runs.
  if not ensureModel(ctx): return false
  var s = ctx.session
  let temp = ctx.cfg.temperature
  let topP = ctx.cfg.topP
  let maxT = ctx.cfg.maxTokens
  var stream: GenerateStreamFn = nil
  if ctx.bs.generate == nil:
    stream = proc(prompt: string, sink: TokenSink): string =
      s.generateTurnStream(prompt, sink, nil, temp, topP, maxT)
  let turn = runHarnessTurn(s, msg,
    generate = ctx.bs.generate,
    maxTokens = ctx.cfg.maxTokens,
    sink = proc(t: string) =
      stdout.write(t)
      stdout.flushFile(),
    generateStream = stream)
  ctx.session = s
  echo ""
  if turn.finalText.len == 0:
    echo "  (no final answer produced)"
  echo "  (" & $turn.iterations & " step" &
       (if turn.iterations != 1: "s" else: "") &
       (if turn.aborted: ", interrupted" else: "") & ")"
  return true

# ---------------------------------------------------------------------------
# Command handlers (each returns an exit code for the invocation)
# ---------------------------------------------------------------------------
proc cmdHelp() =
  echo """nimo repl — unified protocol REPL

Converse (active session):
  send   "<text>"            run one human turn (user -> plan -> tool -> answer)
  queue  "<text>"            buffer (run later with `flush`)
  flush                       flush queued messages as consecutive sends
  steer  "<text>"            a steering/directive turn (same path as send)

Plan (deterministic, offline):
  planner "<goal>"           show the plan the orchestrator would build

Workspace:
  ws status | ws list | ws new <name> | ws switch <path|name>

Session:
  session new [path] | session status

Story:
  story chapter validate <file>
  story chapter write <path> -p "<premise>" [--skip-validate]
  story wiki edit <file> -p "<directive>"

Backend / state:
  cuda status                  GPU probe
  state list                   show the state cache

Meta: help | exit | quit
"""

proc cmdWorkspace(ctx: var ReplContext, tokens: seq[string]): int =
  if tokens.len < 2:
    if ctx.hasWs: echo "[ws] " & ctx.ws.name & " @ " & ctx.ws.path
    else: echo "(no active workspace)"
    echo "usage: ws status | list | new <name> | switch <path|name>"
    return 0
  case tokens[1]
  of "status":
    if ctx.hasWs: workspaceStatus(ctx.ws)
    else: echo "(no active workspace)"
  of "new":
    let name = if tokens.len > 2: tokens[2] else: nowTimestamp()
    let ws = newWorkspace(name)
    ctx.ws = ws
    ctx.hasWs = true
    echo "[ws] created + active: " & ws.name
  of "switch":
    if tokens.len < 3: echo "usage: ws switch <path|name>"; return 0
    let ws = findWorkspace(tokens[2])
    ctx.ws = ws
    ctx.hasWs = true
    setDefaultWorkspace(ws.path)
    echo "[ws] active: " & ws.name & " @ " & ws.path
  of "list":
    let wss = listWorkspaces()
    if wss.len == 0: echo "  (none)"
    for w in wss: echo "  " & w.name
  else:
    echo "unknown ws verb: " & tokens[1]
  return 0

proc cmdSession(ctx: var ReplContext, tokens: seq[string]): int =
  if tokens.len < 2:
    echo "usage: session new [path] | session status"
    return 0
  case tokens[1]
  of "new":
    if not ensureModel(ctx): return 1
    let base = if ctx.hasWs: ctx.ws.path else: ctx.cwd
    if tokens.len > 2:
      ctx.sessionPath = tokens[2]
    else:
      ctx.sessionPath = base / "session.jsonl"
    if fileExists(ctx.sessionPath):
      discard ctx.session.loadSession(ctx.sessionPath)
    echo "[session] active @ " & ctx.sessionPath
  of "status":
    echo "session active: " & (if ctx.hasSession: "yes" else: "no") &
         "  pending: " & $ctx.pending.len
  else:
    echo "unknown session verb: " & tokens[1]
  return 0

proc cmdPlanner(tokens: seq[string]): int =
  var goal = ""
  for t in tokens:
    if t == "planner" or t == "plan": continue
    if goal.len > 0: goal.add " "
    goal.add t
  if goal.len == 0:
    echo "usage: planner \"<goal>\""
    return 0
  let plan = interpret(goal)
  echo "[planner] Goal: " & plan.goal
  echo "[planner] Plan: " & plan.id
  for i, step in plan.steps:
    echo "  " & $i & ". [" & $step.kind & "]" &
         (if step.name.len > 0: " (" & step.name & ")" else: "")
  return 0

proc cmdCuda(): int =
  when defined(harnessOffline):
    echo "offline build — no GPU probe (use an online `nimo repl cuda status`)"
  else:
    let rep = gpuProbe()
    echo rep.describe()
  return 0

proc cmdStateList(ctx: var ReplContext): int =
  let dir = ctx.cfg.stateCacheDir
  if not dirExists(dir):
    echo "state cache empty: " & dir
    return 0
  var total = 0'i64
  var count = 0
  for p in walkFiles(dir / "*.state.bin"):
    total += getFileSize(p)
    inc count
  echo "state cache: " & dir
  echo "  entries: " & $count & "  total: " & $(total div (1024 * 1024)) & " MB"
  return 0

proc cmdStory(ctx: var ReplContext, tokens: seq[string]): int =
  if tokens.len < 2:
    echo "usage: story chapter validate|write …  |  story wiki edit …"
    return 0
  case tokens[1]
  of "chapter":
    if tokens.len < 3: echo "usage: story chapter validate|write"; return 0
    case tokens[2]
    of "validate":
      if tokens.len < 4: echo "usage: story chapter validate <file>"; return 0
      let path = tokens[3]
      if not fileExists(path): echo "no such file: " & path; return 1
      let v = validateChapter(readFile(path))
      echo "[validate] " & v.title
      echo "[validate] " & $v.wordCount & " words, " & $v.paragraphCount &
           " paragraphs, " & $v.repeatingSegments & " repeating"
      echo "[validate] quality: " & $v.quality
      for issue in v.issues: echo "  - " & issue
      return if v.quality == sqPass: 0 else: 1
    of "write":
      if not ensureModel(ctx): return 1
      let premise = flagVal(tokens, "-p")
      if premise.len == 0:
        echo "usage: story chapter write <path> -p \"<premise>\""
        return 0
      let path = if tokens.len > 3: tokens[3] else: "chapter.md"
      ctx.hasSession = true
      let content = generateChapter(ctx.session, 1, "Chapter 1", "", premise)
      writeFile(path, content)
      echo "[story] wrote " & $content.len & " bytes -> " & path
      if not hasFlag(tokens, "--skip-validate"):
        let v = validateChapter(content)
        echo "[validate] quality: " & $v.quality & " (" & $v.wordCount & " words)"
      return 0
    else:
      echo "unknown story chapter verb: " & tokens[2]
  of "wiki":
    if tokens.len < 3: echo "usage: story wiki edit <file> -p \"<directive>\""; return 0
    let directive = flagVal(tokens, "-p")
    if directive.len == 0: echo "missing -p directive"; return 0
    let path = tokens[2]
    if not ensureModel(ctx): return 1
    let base = if fileExists(path): readFile(path) else: ""
    let prompt = "Edit the following wiki entry according to: " & directive &
                 "\n\nCurrent:\n" & (if base.len > 0: base else: "(empty)")
    ctx.hasSession = true
    let outText = ctx.session.generateTurn(prompt)
    writeFile(path, outText)
    echo "[story] wiki updated -> " & path
    return 0
  else:
    echo "unknown story verb: " & tokens[1]
  return 0

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
when isMainModule:
  var cfg = loadConfig()
  var i = 1
  while i <= paramCount():
    let a = paramStr(i)
    if a == "--backend" and i < paramCount():
      inc i
      try:
        cfg.backend = parseBackendKind(paramStr(i))
        cfg.backendSet = true
      except ValueError:
        echo "Error: unknown backend '" & paramStr(i) & "' (cuda|vulkan)"
        quit(1)
    elif a in ["--help", "-h"]:
      cmdHelp()
      quit(0)
    else:
      echo "unknown option: " & a
      quit(1)
    inc i

  var ctx = ReplContext(cfg: cfg, cwd: getCurrentDir())
  let def = getDefaultWorkspace()
  if def.len > 0 and dirExists(def):
    ctx.ws = loadWorkspace(def)
    ctx.hasWs = true

  echo "nimo repl — unified protocol   (type `help`; `quit` to exit)"
  echo "workspace: " & (if ctx.hasWs: ctx.ws.name else: "(none — use ws new/switch)")

  while true:
    stdout.write("nimo> ")
    stdout.flushFile()
    var line: string
    try:
      line = stdin.readLine()
    except EOFError:
      break
    if line.len == 0: continue
    let tokens = tokenize(line)
    if tokens.len == 0: continue
    case tokens[0]
    of "help", "?":
      cmdHelp()
    of "quit", "exit":
      echo "bye."
      break
    of "ws":
      discard cmdWorkspace(ctx, tokens)
    of "session":
      discard cmdSession(ctx, tokens)
    of "planner", "plan":
      discard cmdPlanner(tokens)
    of "send", "steer":
      if tokens.len < 2: echo "usage: send|steer \"<text>\""
      else: discard replTurn(ctx, tokens[1])
    of "queue":
      if tokens.len < 2: echo "usage: queue \"<text>\""
      else:
        ctx.pending.add tokens[1]
        echo "queued (" & $ctx.pending.len & " pending)"
    of "flush":
      for p in ctx.pending: discard replTurn(ctx, p)
      ctx.pending = @[]
      echo "(flushed)"
    of "story":
      discard cmdStory(ctx, tokens)
    of "cuda":
      discard cmdCuda()
    of "state":
      if tokens.len > 1 and tokens[1] == "list": discard cmdStateList(ctx)
      else: echo "usage: state list"
    else:
      echo "unknown command: " & tokens[0] & " (try `help`)"
  quit(0)