import std/[os, times, strutils]

const DefaultLogDir* = "logs"
const DefaultLogFile* = "logs/eternal.log"

proc ensureLogDir*(dirPath: string = DefaultLogDir) =
  if not dirExists(dirPath):
    createDir(dirPath)

proc getTimestamp*(): string =
  now().format("yyyy-MM-dd HH:mm:ss")

proc appendToEternalLog*(msg: string, filePath: string = DefaultLogFile) =
  try:
    let dir = parentDir(filePath)
    if dir.len > 0:
      ensureLogDir(dir)
    let f = open(filePath, fmAppend)
    defer: f.close()
    f.writeLine("[" & getTimestamp() & "] " & msg)
  except IOError, OSError:
    discard

proc logSessionStart*(appName: string, modelPath: string, vocabPath: string, filePath: string = DefaultLogFile) =
  let banner = "=========================================================="
  let msg = "\n" & banner & "\n" &
            "SESSION START: " & appName & "\n" &
            "Timestamp:     " & getTimestamp() & "\n" &
            "Model Path:    " & modelPath & "\n" &
            "Vocab Path:    " & vocabPath & "\n" &
            banner
  appendToEternalLog(msg, filePath)

proc logGenerationRun*(prompt: string, generatedText: string, elapsedSec: float, tokensCount: int, filePath: string = DefaultLogFile) =
  let msPerToken = if tokensCount > 0: elapsedSec / tokensCount.float * 1000.0 else: 0.0
  var msg = "--- TEXT GENERATION ENTRY ---\n"
  msg.add("PROMPT: " & prompt & "\n")
  msg.add("GENERATED COMPLETION:\n" & generatedText & "\n")
  msg.add("STATS: " & $tokensCount & " tokens in " & elapsedSec.formatFloat(ffDecimal, 3) & "s (" & msPerToken.formatFloat(ffDecimal, 2) & " ms/token)\n")
  msg.add("----------------------------")
  appendToEternalLog(msg, filePath)

proc logChatInteraction*(userMsg: string, botReply: string, filePath: string = DefaultLogFile) =
  var msg = "--- CHAT TURN ---\n"
  msg.add("User: " & userMsg & "\n")
  msg.add("Bot:  " & botReply & "\n")
  msg.add("-----------------")
  appendToEternalLog(msg, filePath)
