## NIMWAVE / ILLWAVE Terminal Dashboard for NIMO (RWKV-7 LLM Inference)
## Uses the actual illwave TerminalBuffer API directly.

import std/[os, strutils, strformat, times, random, terminal, unicode]
import illwave as iw
import cli, ./session_manager, ./config, ./tokenizer, ./rwkv, ./logger

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
    role: string
    text: string
    timestamp: string

  DashboardState = object
    session: Session
    messages: seq[ChatMessage]
    inputBuffer: string
    statusText: string

proc formatTimeNow(): string = now().format("HH:mm:ss")

proc initDashboard(modelPath, vocabPath: string): DashboardState =
  result.statusText = "Loading model..."
  result.session = newSession(".")
  result.session.initModel(modelPath, vocabPath)

  let sysPrompt = "User: hi\n\nBot: Hello! How can I help you today?\n\n"
  let sysTokens = result.session.tok.encode(sysPrompt)
  if sysTokens.len > 0:
    discard result.session.model.evalSequenceInChunks(sysTokens, DefaultChunkSize, result.session.state, result.session.logits)

  result.messages.add(ChatMessage(role: "User", text: "hi", timestamp: formatTimeNow()))
  result.messages.add(ChatMessage(role: "Bot", text: "Hello! How can I help you today?", timestamp: formatTimeNow()))
  result.statusText = &"Ready (nVocab={result.session.model.nVocab}, nLayer={result.session.model.nLayer})"

proc handleTurn(app: var DashboardState) =
  if app.inputBuffer.len == 0: return
  let userMsg = app.inputBuffer
  app.inputBuffer = ""
  app.messages.add(ChatMessage(role: "User", text: userMsg, timestamp: formatTimeNow()))
  app.statusText = "Thinking..."
  let reply = app.session.generateTurn(userMsg)
  app.messages.add(ChatMessage(role: "Bot", text: reply, timestamp: formatTimeNow()))
  app.statusText = "Ready"

proc putCell(tb: var iw.TerminalBuffer, x, y: int, ch: string, fg: iw.ForegroundColor, bg: iw.BackgroundColor) =
  tb[x, y] = iw.TerminalChar(ch: ch.toRunes[0], fg: fg, bg: bg, style: {})

proc renderDashboard(app: var DashboardState) =
  let w = terminalWidth()
  let h = terminalHeight()

  if w < 40 or h < 10:
    echo "Terminal too small (need 40x10)"
    return

  var tb = iw.initTerminalBuffer(w, h)
  iw.init(fullScreen = true)

  let cCyan = iw.fgCyan
  let cBlack = iw.bgBlack
  let cWhite = iw.fgWhite
  let cGreen = iw.fgGreen
  let cMagenta = iw.fgMagenta
  let cYellow = iw.fgYellow

  # Title
  tb.setForegroundColor(cCyan)
  tb.setBackgroundColor(cBlack)
  tb.write(1, 0, " NIMO - RWKV-7 TUI ")
  tb.setForegroundColor(cYellow)
  tb.write(w - 20, 0, app.statusText)

  # Panels
  let leftW = max(20, (w.float * 0.70).int)
  let rightW = w - leftW
  let mainH = h - 4

  # Left panel border
  for x in 1 ..< leftW - 1:
    putCell(tb, x, 2, HLine, cCyan, cBlack)
    putCell(tb, x, 2 + mainH - 1, HLine, cCyan, cBlack)
  for y in 3 ..< 2 + mainH - 1:
    putCell(tb, 0, y, VLine, cCyan, cBlack)
    putCell(tb, leftW - 1, y, VLine, cCyan, cBlack)
  putCell(tb, 0, 2, CornerTL, cCyan, cBlack)
  putCell(tb, leftW - 1, 2, CornerTR, cCyan, cBlack)
  putCell(tb, 0, 2 + mainH - 1, CornerBL, cCyan, cBlack)
  putCell(tb, leftW - 1, 2 + mainH - 1, CornerBR, cCyan, cBlack)

  tb.setForegroundColor(cGreen)
  tb.write(2, 2, " Conversation ")

  var lineIdx = 3
  for msg in app.messages:
    if lineIdx >= 2 + mainH - 1: break
    let color = if msg.role == "User": cCyan else: cGreen
    tb.setForegroundColor(color)
    tb.write(2, lineIdx, &"[{msg.timestamp}] {msg.role}: ")
    tb.setForegroundColor(cWhite)
    tb.write(msg.role.len + 12, lineIdx, msg.text)
    inc lineIdx
    inc lineIdx

  # Right panel border
  for x in 1 ..< rightW - 1:
    putCell(tb, leftW + x, 2, HLine, cCyan, cBlack)
    putCell(tb, leftW + x, 2 + mainH - 1, HLine, cCyan, cBlack)
  for y in 3 ..< 2 + mainH - 1:
    putCell(tb, leftW, y, VLine, cCyan, cBlack)
    putCell(tb, leftW + rightW - 1, y, VLine, cCyan, cBlack)
  putCell(tb, leftW, 2, CornerTL, cCyan, cBlack)
  putCell(tb, leftW + rightW - 1, 2, CornerTR, cCyan, cBlack)
  putCell(tb, leftW, 2 + mainH - 1, CornerBL, cCyan, cBlack)
  putCell(tb, leftW + rightW - 1, 2 + mainH - 1, CornerBR, cCyan, cBlack)

  tb.setForegroundColor(cMagenta)
  tb.write(leftW + 2, 2, " Info ")

  var r = 4
  tb.setForegroundColor(cWhite)
  tb.write(leftW + 2, r, &"Threads: {DefaultThreads}"); inc r
  tb.write(leftW + 2, r, &"GPU: {DefaultGpuLayers} layers"); inc r
  tb.write(leftW + 2, r, &"Temp: {DefaultTemp} | TopP: {DefaultTopP}"); inc r
  inc r
  tb.setForegroundColor(cYellow)
  tb.write(leftW + 2, r, "Keys:"); inc r
  tb.setForegroundColor(cCyan)
  tb.write(leftW + 2, r, " Enter - send"); inc r
  tb.write(leftW + 2, r, " ESC - exit"); inc r

  # Input bar
  tb.setForegroundColor(cYellow)
  tb.write(1, h - 2, "> " & app.inputBuffer)

  iw.display(tb)
  iw.deinit()

proc main() =
  let modelPath = resolveModelPath(if paramCount() > 0: paramStr(1) else: DefaultModelPath)
  let vocabPath = if paramCount() > 1: paramStr(2) else: DefaultVocabPath

  logSessionStart("NIMO Dashboard", modelPath, vocabPath)

  var app = initDashboard(modelPath, vocabPath)

  setControlCHook(proc() {.noconv.} =
    iw.deinit()
    quit(0))
  defer: iw.deinit()

  while true:
    renderDashboard(app)
    let key = iw.getKey()

    case key
    of iw.Key.Escape, iw.Key.Q:
      break
    of iw.Key.Enter:
      app.handleTurn()
    of iw.Key.Backspace:
      if app.inputBuffer.len > 0:
        app.inputBuffer.setLen(app.inputBuffer.len - 1)
    else:
      if key != iw.Key.None and ord(key) >= 32 and ord(key) <= 126:
        app.inputBuffer.add($key)

when isMainModule:
  main()
