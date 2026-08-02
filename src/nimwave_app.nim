## NIMWAVE / ILLWAVE Terminal Dashboard for NIMO (RWKV-7 LLM Inference)
## Uses the actual illwave TerminalBuffer API directly.

import std/[os, strutils, strformat, times, random, terminal, unicode]
import illwave as iw
import cli, ./rwkv, ./config, ./tokenizer, ./logger, ./sampling

# ── Box-drawing character constants ───────────────────────────────────────────
const
  HLine  = "─"
  VLine  = "│"
  CornerTL = "┌"
  CornerTR = "┐"
  CornerBL = "└"
  CornerBR = "┘"

type
  ChatMessage = object
    role: string      # "User" or "Bot"
    text: string
    timestamp: string

  AppState = object
    modelPath: string
    vocabPath: string
    model: RwkvModel
    tok: WorldTokenizer
    stateBuf: seq[float32]
    logitsBuf: seq[float32]
    messages: seq[ChatMessage]
    inputBuffer: string
    statusText: string
    tokensGenerated: int
    elapsedSec: float
    isGenerating: bool
    rng: Rand

proc formatTimeNow(): string = now().format("HH:mm:ss")

proc initAppState(modelPath, vocabPath: string): AppState =
  result.modelPath = modelPath
  result.vocabPath = vocabPath
  result.statusText = "Initializing RWKV Model..."
  result.rng = initRand(cpuTime().int64)

  if fileExists(vocabPath):
    result.tok = loadWorldTokenizer(vocabPath)

  if fileExists(modelPath):
    result.model = initRwkvModel(modelPath, nThreads = DefaultThreads, nGpuLayers = DefaultGpuLayers)
    result.stateBuf = result.model.newState()
    result.logitsBuf = result.model.newLogits()

    # Pre-evaluate default system greeting
    let sysPrompt = "User: hi\n\nBot: Hello! How can I help you today?\n\n"
    let sysTokens = result.tok.encode(sysPrompt)
    if sysTokens.len > 0:
      discard result.model.evalSequenceInChunks(sysTokens, chunkSize = DefaultChunkSize, result.stateBuf, result.logitsBuf)

    result.messages.add(ChatMessage(role: "User", text: "hi", timestamp: formatTimeNow()))
    result.messages.add(ChatMessage(role: "Bot", text: "Hello! How can I help you today?", timestamp: formatTimeNow()))
    result.statusText = &"Model Ready! (nVocab={result.model.nVocab}, nLayer={result.model.nLayer})"
  else:
    result.statusText = &"Error: Model file '{modelPath}' not found!"

proc processUserTurn(app: var AppState) =
  if app.model == nil or app.tok == nil: return
  let prompt = app.inputBuffer.strip()
  app.inputBuffer = ""
  if prompt.len == 0: return

  if prompt == "/reset":
    app.stateBuf = app.model.newState()
    app.logitsBuf = app.model.newLogits()
    let sysPrompt = "User: hi\n\nBot: Hello! How can I help you today?\n\n"
    let sysTokens = app.tok.encode(sysPrompt)
    if sysTokens.len > 0:
      discard app.model.evalSequenceInChunks(sysTokens, chunkSize = DefaultChunkSize, app.stateBuf, app.logitsBuf)
    app.messages.setLen(0)
    app.messages.add(ChatMessage(role: "User", text: "hi", timestamp: formatTimeNow()))
    app.messages.add(ChatMessage(role: "Bot", text: "Hello! How can I help you today?", timestamp: formatTimeNow()))
    app.statusText = "Chat Session Reset."
    return

  app.messages.add(ChatMessage(role: "User", text: prompt, timestamp: formatTimeNow()))
  app.statusText = "Evaluating Prompt..."

  let turnPrompt = "User: " & prompt & "\n\nBot:"
  let turnTokens = app.tok.encode(turnPrompt)

  if turnTokens.len > 0:
    discard app.model.evalSequenceInChunks(turnTokens, chunkSize = DefaultChunkSize, app.stateBuf, app.logitsBuf)

  var botReply = ""
  var validState = app.stateBuf
  let t0 = cpuTime()
  var genTokens = 0

  for step in 0 ..< 200:
    let nextToken = sampleLogits(app.logitsBuf, temperature = DefaultTemp, topP = DefaultTopP, rng = app.rng)
    if nextToken == 0:
      app.stateBuf = validState
      break

    let tokenStr = app.tok.decodeToken(nextToken.uint32)
    botReply.add(tokenStr)
    inc genTokens

    if endsWithStopSequence(botReply):
      app.stateBuf = validState
      break

    if not app.model.eval(nextToken.uint32, app.stateBuf, app.logitsBuf):
      break
    validState = app.stateBuf

  app.elapsedSec = cpuTime() - t0
  app.tokensGenerated = genTokens
  app.messages.add(ChatMessage(role: "Bot", text: botReply.strip(), timestamp: formatTimeNow()))

  # Terminate turn state cleanly with double newline
  let endTurnTokens = app.tok.encode("\n\n")
  if endTurnTokens.len > 0:
    discard app.model.evalSequence(endTurnTokens, app.stateBuf, app.logitsBuf)

  let msPerTok = if genTokens > 0: app.elapsedSec / genTokens.float * 1000.0 else: 0.0
  app.statusText = &"Done! Generated {genTokens} tokens in {app.elapsedSec:.2f}s ({msPerTok:.1f} ms/token)"

proc putCell(tb: var iw.TerminalBuffer, x, y: int, ch: string, fg: iw.ForegroundColor, bg: iw.BackgroundColor) =
  tb[x, y] = iw.TerminalChar(ch: ch.toRunes[0], fg: fg, bg: bg, style: {})

proc renderDashboard(app: var AppState) =
  let w = terminalWidth()
  let h = terminalHeight()

  if w < 40 or h < 10:
    echo "Terminal window too small! Need at least 40x10."
    return

  var tb = iw.initTerminalBuffer(w, h)
  iw.init(fullScreen = true)

  # ── Title Header Box (rows 0-2) ──────────────────────────────────────────
  tb.setForegroundColor(iw.fgCyan)
  tb.setBackgroundColor(iw.bgBlack)
  tb.write(1, 0, " NIMO - NIM RWKV-7 TUI DASHBOARD (NIMWAVE / ILLWAVE) ")
  tb.setForegroundColor(iw.fgYellow)
  tb.write(w - 26, 0, "Status: Ready ")

  # ── Left Messages Panel (x=0, y=3, width=70% of w) ──────────────────────
  let leftW = max(20, (w.float * 0.70).int)
  let rightW = w - leftW
  let mainH = h - 6

  let cCyan = iw.fgCyan
  let cBlack = iw.bgBlack
  let cWhite = iw.fgWhite
  let cGreen = iw.fgGreen
  let cMagenta = iw.fgMagenta
  let cYellow = iw.fgYellow

  # Left panel box
  for x in 1 ..< leftW - 1:
    putCell(tb, x, 3,                HLine, cCyan, cBlack)
    putCell(tb, x, 3 + mainH - 1,    HLine, cCyan, cBlack)
  for y in 4 ..< 3 + mainH - 1:
    putCell(tb, 0,        y,         VLine, cCyan, cBlack)
    putCell(tb, leftW - 1, y,        VLine, cCyan, cBlack)
  putCell(tb, 0,        3,          CornerTL, cCyan, cBlack)
  putCell(tb, leftW - 1, 3,         CornerTR, cCyan, cBlack)
  putCell(tb, 0,        3 + mainH - 1,  CornerBL, cCyan, cBlack)
  putCell(tb, leftW - 1, 3 + mainH - 1, CornerBR, cCyan, cBlack)

  tb.setForegroundColor(cGreen)
  tb.setBackgroundColor(cBlack)
  tb.write(2, 3, " Conversation History ")

  var lineIdx = 4
  for msg in app.messages:
    if lineIdx >= 3 + mainH - 2: break
    let color = if msg.role == "User": cCyan else: cGreen
    tb.setForegroundColor(color)
    tb.setBackgroundColor(cBlack)
    tb.write(2, lineIdx, &"[{msg.timestamp}] {msg.role}: ")
    tb.setForegroundColor(cWhite)
    let indent = msg.role.len + 12
    tb.write(indent, lineIdx, msg.text)
    inc lineIdx
    inc lineIdx

  # ── Right Telemetry Panel (x=leftW, y=3, width=rightW) ───────────────────
  for x in 1 ..< rightW - 1:
    putCell(tb, leftW + x, 3,                HLine, cCyan, cBlack)
    putCell(tb, leftW + x, 3 + mainH - 1,    HLine, cCyan, cBlack)
  for y in 4 ..< 3 + mainH - 1:
    putCell(tb, leftW,         y,             VLine, cCyan, cBlack)
    putCell(tb, leftW + rightW - 1, y,        VLine, cCyan, cBlack)
  putCell(tb, leftW,         3,              CornerTL, cCyan, cBlack)
  putCell(tb, leftW + rightW - 1, 3,         CornerTR, cCyan, cBlack)
  putCell(tb, leftW,         3 + mainH - 1,  CornerBL, cCyan, cBlack)
  putCell(tb, leftW + rightW - 1, 3 + mainH - 1, CornerBR, cCyan, cBlack)

  tb.setForegroundColor(cMagenta)
  tb.setBackgroundColor(cBlack)
  tb.write(leftW + 2, 3, " System & Model Telemetry ")

  var rightLine = 5
  tb.setForegroundColor(cWhite)
  tb.setBackgroundColor(cBlack)
  tb.write(leftW + 2, rightLine, &"Model: RWKV-7 2.9B"); inc rightLine
  tb.write(leftW + 2, rightLine, &"Threads: {DefaultThreads}"); inc rightLine
  tb.write(leftW + 2, rightLine, &"GPU Layers: {DefaultGpuLayers}"); inc rightLine
  tb.write(leftW + 2, rightLine, &"Temp: {DefaultTemp:.1f} | Top-P: {DefaultTopP:.1f}"); inc rightLine
  inc rightLine
  tb.setForegroundColor(cYellow)
  tb.write(leftW + 2, rightLine, "Commands:"); inc rightLine
  tb.setForegroundColor(cCyan)
  tb.write(leftW + 2, rightLine, " /reset - Reset state"); inc rightLine
  tb.write(leftW + 2, rightLine, " ESC/Ctrl+C - Exit"); inc rightLine
  inc rightLine
  if app.tokensGenerated > 0:
    tb.setForegroundColor(cGreen)
    tb.write(leftW + 2, rightLine, &"Last Gen: {app.tokensGenerated} tokens"); inc rightLine
    tb.write(leftW + 2, rightLine, &"Time: {app.elapsedSec:.2f} s")

  # ── Bottom Status & Input Bar (rows h-3 to h-1) ─────────────────────────
  tb.setForegroundColor(cYellow)
  tb.setBackgroundColor(cBlack)
  tb.write(1, h - 3, &" {app.statusText} ")
  tb.setForegroundColor(cCyan)
  tb.write(1, h - 2, "> " & app.inputBuffer)

  iw.display(tb)
  iw.deinit()

proc main() =
  let modelPath = resolveModelPath(if paramCount() > 0: paramStr(1) else: DefaultModelPath)
  let vocabPath = if paramCount() > 1: paramStr(2) else: DefaultVocabPath

  logSessionStart("RWKV NimWave TUI Dashboard", modelPath, vocabPath)

  var app = initAppState(modelPath, vocabPath)

  setControlCHook(proc() {.noconv.} =
    iw.deinit()
    echo "NIMO TUI session ended."
    quit(0))
  defer: iw.deinit()

  while true:
    renderDashboard(app)
    let key = iw.getKey()

    case key
    of iw.Key.Escape, iw.Key.Q:
      break
    of iw.Key.Enter:
      app.processUserTurn()
    of iw.Key.Backspace:
      if app.inputBuffer.len > 0:
        app.inputBuffer.setLen(app.inputBuffer.len - 1)
    else:
      if key != iw.Key.None and ord(key) >= 32 and ord(key) <= 126:
        app.inputBuffer.add($key)

when isMainModule:
  main()
