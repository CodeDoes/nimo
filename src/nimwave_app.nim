## NIMWAVE / ILLWAVE Terminal Dashboard for NIMO (RWKV-7 LLM Inference)

import std/[os, strutils, strformat, times, random]
import illwave as iw
import nimwave as nw
import ./rwkv, ./config, ./tokenizer, ./logger, ./sampling, ./macros

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

proc formatTimeNow(): string =
  now().format("HH:mm:ss")

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

proc processUserTurn(app: var AppState, input: string) =
  if app.model == nil or app.tok == nil: return
  let prompt = input.strip()
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

proc renderDashboard(app: var AppState) =
  iw.tbClear()
  let w = iw.terminalWidth()
  let h = iw.terminalHeight()

  if w < 40 or h < 10:
    iw.tbPrint(0, 0, fgRed, bgBlack, "Terminal window too small!")
    iw.tbPresent()
    return

  # Draw Title Header Box
  iw.drawBox(0, 0, w, 3)
  iw.tbPrint(2, 1, fgCyan, bgBlack, " NIMO - NIM RWKV-7 TUI DASHBOARD (NIMWAVE / ILLWAVE) ")
  iw.tbPrint(w - 25, 1, fgYellow, bgBlack, &"Status: Ready ")

  # Draw Left Messages Panel
  let leftW = (w.float * 0.70).int
  let rightW = w - leftW
  let mainH = h - 6

  iw.drawBox(0, 3, leftW, mainH)
  iw.tbPrint(2, 3, fgGreen, bgBlack, " Conversation History ")

  var lineIdx = 4
  for msg in app.messages:
    if lineIdx >= 3 + mainH - 2: break
    let color = if msg.role == "User": fgCyan else: fgGreen
    iw.tbPrint(2, lineIdx, color, bgBlack, &"[{msg.timestamp}] {msg.role}: ")
    let indent = msg.role.len + 12
    iw.tbPrint(indent, lineIdx, fgWhite, bgBlack, msg.text)
    inc lineIdx
    inc lineIdx

  # Draw Right Telemetry Panel
  iw.drawBox(leftW, 3, rightW, mainH)
  iw.tbPrint(leftW + 2, 3, fgMagenta, bgBlack, " System & Model Telemetry ")

  var rightLine = 5
  iw.tbPrint(leftW + 2, rightLine, fgWhite, bgBlack, &"Model: RWKV-7 2.9B"); inc rightLine
  iw.tbPrint(leftW + 2, rightLine, fgWhite, bgBlack, &"Threads: {DefaultThreads}"); inc rightLine
  iw.tbPrint(leftW + 2, rightLine, fgWhite, bgBlack, &"GPU Layers: {DefaultGpuLayers}"); inc rightLine
  iw.tbPrint(leftW + 2, rightLine, fgWhite, bgBlack, &"Temp: {DefaultTemp:.1f} | Top-P: {DefaultTopP:.1f}"); inc rightLine
  inc rightLine
  iw.tbPrint(leftW + 2, rightLine, fgYellow, bgBlack, "Commands:"); inc rightLine
  iw.tbPrint(leftW + 2, rightLine, fgCyan, bgBlack, " /reset - Reset state"); inc rightLine
  iw.tbPrint(leftW + 2, rightLine, fgCyan, bgBlack, " ESC/Ctrl+C - Exit"); inc rightLine
  inc rightLine
  if app.tokensGenerated > 0:
    iw.tbPrint(leftW + 2, rightLine, fgGreen, bgBlack, &"Last Gen: {app.tokensGenerated} tokens"); inc rightLine
    iw.tbPrint(leftW + 2, rightLine, fgGreen, bgBlack, &"Time: {app.elapsedSec:.2f} s"); inc rightLine

  # Draw Bottom Status & Input Bar
  iw.drawBox(0, h - 3, w, 3)
  iw.tbPrint(2, h - 3, fgYellow, bgBlack, &" {app.statusText} ")
  iw.tbPrint(2, h - 2, fgCyan, bgBlack, "> " & app.inputBuffer)

  iw.tbPresent()

proc main() =
  let modelPath = resolveModelPath(if paramCount() > 0: paramStr(1) else: DefaultModelPath)
  let vocabPath = if paramCount() > 1: paramStr(2) else: DefaultVocabPath

  logSessionStart("RWKV NimWave TUI Dashboard", modelPath, vocabPath)

  iw.illwaveInit()
  setControlCHook(proc() {.noconv.} =
    iw.illwaveDeinit()
    echo "NIMO TUI session ended."
    quit(0))
  defer: iw.illwaveDeinit()

  var app = initAppState(modelPath, vocabPath)

  while true:
    renderDashboard(app)
    let key = iw.getKey()

    case key.sym
    of iw.Key.Escape, iw.Key.q:
      break
    of iw.Key.Enter:
      if app.inputBuffer.len > 0:
        let inp = app.inputBuffer
        app.inputBuffer = ""
        app.processUserTurn(inp)
    of iw.Key.Backspace:
      if app.inputBuffer.len > 0:
        app.inputBuffer.setLen(app.inputBuffer.len - 1)
    else:
      if key.ch != '\0' and ord(key.ch) >= 32 and ord(key.ch) <= 126:
        app.inputBuffer.add(key.ch)

when isMainModule:
  main()
