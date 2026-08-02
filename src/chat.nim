## RWKV Interactive TUI Chat — uses illwave terminal buffer for styled output

import std/[os, strutils, strformat, random, times, terminal]
import cli, rwkv, config, tokenizer, logger, sampling, macros

proc startTuiChat() =
  let rawModelPath = if paramCount() > 0: paramStr(1) else: DefaultModelPath
  let modelPath = resolveModelPath(rawModelPath)
  let vocabPath = if paramCount() > 1: paramStr(2) else: DefaultVocabPath
  let bakedStatePath = if paramCount() > 2: paramStr(3) else: ""
  let temp = DefaultTemp
  let topP = DefaultTopP

  logSessionStart("RWKV TUI Chat Session (4-bit GGML)", modelPath, vocabPath)

  printBanner "RWKV Interactive TUI Chat"
  printConfig(modelPath, vocabPath)
  echo "Commands:   /reset (clear history), /quit (exit)"
  echo ""

  if not fileExists(modelPath):
    printError &"Error: Model file not found at '{modelPath}'"
    appendToEternalLog &"Error: Model file not found at '{modelPath}'"
    return

  let tok = loadWorldTokenizer(vocabPath)
  printSuccess "Vocab loaded successfully!"

  withModel(modelPath, DefaultThreads, DefaultGpuLayers, model):
    printSuccess &"Model loaded! (nVocab={model.nVocab}, nLayer={model.nLayer})"
    echo ""

    var state = model.newState()
    var logits = model.newLogits()
    var rng = initRand(cpuTime().int64)

    # Initial prompt / system setup
    let initialUserMsg = "hi"
    let initialBotMsg = "Hello! How can I help you today?"
    let sysPrompt = "User: " & initialUserMsg & "\n\nBot: " & initialBotMsg & "\n\n"
    var sysTokens = tok.encode(sysPrompt)

    if bakedStatePath.len > 0 and fileExists(bakedStatePath):
      printWarn &"Loading pre-baked state from '{bakedStatePath}'..."
      state.loadState(bakedStatePath)
    elif sysTokens.len > 0:
      checkOk(model.evalSequenceInChunks(sysTokens, chunkSize = DefaultChunkSize, state, logits),
              "Failed to evaluate system prompt")

    styledEcho(styleBright, fgCyan, "User: ", initialUserMsg)
    styledEcho(styleBright, fgGreen, "Bot:  ", initialBotMsg)

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
      if inputLine.len == 0:
        continue

      if inputLine == "/quit" or inputLine == "/exit":
        printWarn "Goodbye!"
        appendToEternalLog "User quit chat session."
        break
      elif inputLine == "/reset":
        state = model.newState()
        logits = model.newLogits()
        if sysTokens.len > 0:
          discard model.evalSequenceInChunks(sysTokens, chunkSize = DefaultChunkSize, state, logits)
        printWarn "Chat session reset."
        styledEcho(styleBright, fgCyan, "User: ", initialUserMsg)
        styledEcho(styleBright, fgGreen, "Bot:  ", initialBotMsg)
        appendToEternalLog "Chat session reset by user."
        continue

      # Ensure preceding context terminates with double newlines
      let turnPrompt = "User: " & inputLine & "\n\nBot:"
      var turnTokens = tok.encode(turnPrompt)

      if turnTokens.len > 0:
        benchmarkStep("chat_turn_eval"):
          if not model.evalSequenceInChunks(turnTokens, chunkSize = DefaultChunkSize, state, logits):
            printError "Error evaluating user prompt."
            appendToEternalLog "Error evaluating prompt: " & inputLine
            continue

      stdout.write("Bot:  ")
      stdout.flushFile()

      var botReply = ""
      var buffer = ""
      var validState = state

      for step in 0 ..< 200:
        streamToken(model, state, logits, tok, temp, topP, rng, nextToken, tokenStr):
          if nextToken == 0: # Token 0 = End of Text (EOS)
            state = validState
            break

          botReply.add(tokenStr)
          buffer.add(tokenStr)

          if endsWithStopSequence(botReply):
            state = validState
            break

          if not model.eval(nextToken.uint32, state, logits):
            break

          let prefixLen = maxStopPrefixLen(buffer)
          let safeLen = buffer.len - prefixLen
          if safeLen > 0:
            stdout.write(buffer[0 ..< safeLen])
            stdout.flushFile()
            buffer = buffer[safeLen .. ^1]
            validState = state

      if buffer.len > 0 and not endsWithStopSequence(botReply):
        stdout.write(buffer)
        stdout.flushFile()

      echo ""
      logChatInteraction(inputLine, botReply.strip())

      # Evaluate double newline into state to cleanly terminate the turn context for next turn
      let endTurnTokens = tok.encode("\n\n")
      if endTurnTokens.len > 0:
        discard model.evalSequence(endTurnTokens, state, logits)

when isMainModule:
  startTuiChat()
