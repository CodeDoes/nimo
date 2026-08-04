## RWKV State Baker — CLI with session management

import std/[os, strutils, strformat, times]
import cli, ./session_manager, ./config, ./tokenizer, ./rwkv, ./logger, ./macros

proc main() =
  let modelPath = resolveModelPath(if paramCount() > 0: paramStr(1) else: DefaultModelPath)
  let promptArg = if paramCount() > 1: paramStr(2) else: DefaultPrompt
  let outStatePath = if paramCount() > 2: paramStr(3) else: "baked_state.bin"
  let vocabPath = if paramCount() > 3: paramStr(4) else: DefaultVocabPath

  let promptText = if fileExists(promptArg): readFile(promptArg) else: promptArg

  logSessionStart("RWKV Bake State", modelPath, vocabPath)
  printBanner "RWKV State Baker"
  printConfig(modelPath, vocabPath)
  echo "Output: ", outStatePath
  echo "Prompt: ", promptText.len, " chars"
  echo SepThin

  if not fileExists(modelPath):
    printError &"Model not found: {modelPath}"
    return

  var s = newSession(".")
  s.initModel(modelPath, vocabPath)

  var promptTokens = s.tok.encode(promptText)
  if promptTokens.len == 0:
    printError "Empty prompt."
    return

  printInfo &"Encoding prompt -> {promptTokens.len} tokens"

  var elapsed = 0.0
  timeBlock(elapsed):
    benchmarkStep("bake_eval"):
      checkOk(s.model.evalSequenceInChunks(promptTokens, DefaultChunkSize, s.state, s.logits),
              "Failed to evaluate prompt")

  s.state.saveState(outStatePath)

  let fileSize = getFileSize(outStatePath)
  let msPerTok = elapsed / promptTokens.len.float * 1000.0

  echo ""
  echo BannerSep
  printSuccess &"Baked {promptTokens.len} tokens into '{outStatePath}'"
  printSuccess &"State size: {fileSize} bytes ({fileSize.float / 1024.0:.2f} KB)"
  printSuccess &"Time: {elapsed:.3f}s ({msPerTok:.2f} ms/token)"
  echo BannerSep
  appendToEternalLog &"Baked state: {promptTokens.len} tokens, {fileSize} bytes, {elapsed:.3f}s"

when isMainModule:
  main()
