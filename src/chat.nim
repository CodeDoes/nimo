## RWKV Interactive Chat — CLI with session management

import std/[os, strutils, strformat, terminal]
import cli, ./session, ./config, ./tokenizer, ./rwkv, ./logger

proc main() =
  let modelPath = resolveModelPath(if paramCount() > 0: paramStr(1) else: DefaultModelPath)
  let vocabPath = if paramCount() > 1: paramStr(2) else: DefaultVocabPath
  let bakedStatePath = if paramCount() > 2: paramStr(3) else: ""

  logSessionStart("RWKV Chat", modelPath, vocabPath)
  printBanner "RWKV Interactive Chat"
  printConfig(modelPath, vocabPath)
  echo "Commands: /reset, /quit"
  echo ""

  if not fileExists(modelPath):
    printError &"Model not found: {modelPath}"
    return

  var s = initSession(modelPath, vocabPath)

  if bakedStatePath.len > 0 and fileExists(bakedStatePath):
    printWarn &"Loading baked state from '{bakedStatePath}'"
    s.state.loadState(bakedStatePath)
  else:
    let sysPrompt = "User: hi\n\nBot: Hello! How can I help you today?\n\n"
    let sysTokens = s.tok.encode(sysPrompt)
    if sysTokens.len > 0:
      discard s.model.evalSequenceInChunks(sysTokens, DefaultChunkSize, s.state, s.logits)
    styledEcho(styleBright, fgCyan, "User: hi")
    styledEcho(styleBright, fgGreen, "Bot:  Hello! How can I help you today?")

  while true:
    stdout.write("\nUser: ")
    stdout.flushFile()
    var inputLine: string
    try:
      inputLine = readLine(stdin)
    except IOError, EOFError:
      printWarn "\nGoodbye!"
      break

    inputLine = inputLine.strip()
    if inputLine.len == 0: continue

    if inputLine == "/quit" or inputLine == "/exit":
      printWarn "Goodbye!"
      break
    elif inputLine == "/reset":
      s = initSession(modelPath, vocabPath)
      let sysPrompt = "User: hi\n\nBot: Hello! How can I help you today?\n\n"
      let sysTokens = s.tok.encode(sysPrompt)
      if sysTokens.len > 0:
        discard s.model.evalSequenceInChunks(sysTokens, DefaultChunkSize, s.state, s.logits)
      styledEcho(styleBright, fgCyan, "User: hi")
      styledEcho(styleBright, fgGreen, "Bot:  Hello! How can I help you today?")
      continue

    let reply = s.generateTurn(inputLine)
    echo "Bot:  ", reply
    logChatInteraction(inputLine, reply)

when isMainModule:
  main()
