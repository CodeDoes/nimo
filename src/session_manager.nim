## Session Manager for NIMO Harness
## Manages messages, tools, and JSONL logging.
##
## Build with `-d:harnessOffline` to strip the RWKV model backend, letting the
## harness (and unit tests) run without rwkv.cpp / a GPU model. Generation is
## injected as a parameter (`generate: GenerateFn`); pass `nil` to use the real
## model on this session (offline builds always get the placeholder).

import std/[json, times, strutils, os, random, tables]
import ./config
when not defined(harnessOffline):
  import ./rwkv, ./tokenizer, ./sampling, ./macros, ./rwkv/state/cache

type
  ContentKind* = enum
    ckText, ckThinking, ckToolCall, ckToolResult

  ContentPart* = object
    kind*: ContentKind
    text*: string
    toolCallId*: string
    toolName*: string
    arguments*: string
    thinkingSignature*: string

  MessageRole* = enum
    mrUser, mrAssistant, mrToolResult

  Message* = object
    id*: string
    parentId*: string
    timestamp*: string
    role*: MessageRole
    content*: seq[ContentPart]
    stopReason*: string

  ToolHandler* = proc(args: string): string
  # GenerateFn is defined in ./config — the model-generation seam that tests
  # mock with precanned replies. The session itself is never stubbed.

  Session* = ref object
    id*: string
    timestamp*: string
    cwd*: string
    messages*: seq[Message]
    branches*: seq[string]
    activeBranch*: int
    tools*: Table[string, ToolHandler]
    when not defined(harnessOffline):
      model*: RwkvModel
      tok*: WorldTokenizer
      state*: seq[float32]
      logits*: seq[float32]
      rng*: Rand

proc nowStr*(): string =
  let t = now()
  return t.format("yyyy") & "-" & t.format("MM") & "-" & t.format("dd") & "T" &
         t.format("HH") & ":" & t.format("mm") & ":" & t.format("ss")

proc newSession*(cwd: string = "."): Session =
  result = Session.new()
  result.id = "sess_" & now().format("yyyyMMddHHmmss")
  result.timestamp = nowStr()
  result.cwd = cwd
  result.activeBranch = 0
  result.tools = initTable[string, ToolHandler]()

when not defined(harnessOffline):
  proc initModel*(s: var Session, modelPath, vocabPath: string,
                  gpuLayers: int = DefaultGpuLayers,
                  systemPrompt: string = "",
                  stateCacheDir: string = "",
                  bakeContext: bool = false) =
    s.tok = loadWorldTokenizer(vocabPath)
    s.model = initRwkvModel(modelPath, DefaultThreads, gpuLayers.uint32)
    s.logits = s.model.newLogits()
    s.rng = initRand(cpuTime().int64)
    s.state = s.model.newState()
    # RFC 8000: bake the fixed system context once, resume from it on later runs.
    if systemPrompt.len > 0 and stateCacheDir.len > 0:
      let cache = initStateCache(stateCacheDir)
      s.state = cache.bakeContext(s.model, s.tok, modelPath, vocabPath, systemPrompt)

proc generateTurn*(s: var Session, userMsg: string, generate: GenerateFn = nil,
                   temp: float32 = DefaultTemp, topP: float32 = DefaultTopP,
                   maxTokens: int = 200): string =
  ## Generates a reply. If a `generate` fn is supplied (test mock, offline
  ## stub), call it; otherwise run the real RWKV model attached to this session.
  if generate != nil:
    return generate(userMsg)
  when not defined(harnessOffline):
    if s.model == nil:
      return "[nimo] Model not loaded"
    let turnPrompt = "User: " & userMsg & "\n\nBot:"
    let turnTokens = s.tok.encode(turnPrompt)
    checkOk(s.model.evalSequenceInChunks(turnTokens, DefaultChunkSize, s.state, s.logits),
            "Failed to evaluate prompt")

    var reply = ""
    var validState = s.state
    for step in 0 ..< maxTokens:
      let token = sampleLogits(s.logits, temperature = temp, topP = topP, rng = s.rng)
      if token == 0:
        s.state = validState
        break
      let tokenStr = s.tok.decodeToken(token.uint32)
      reply.add(tokenStr)
      if endsWithStopSequence(reply):
        s.state = validState
        break
      if not s.model.eval(token.uint32, s.state, s.logits):
        break
      validState = s.state

    # End-of-turn cleanup
    let endTokens = s.tok.encode("\n\n")
    if endTokens.len > 0:
      discard s.model.evalSequence(endTokens, s.state, s.logits)

    return reply.strip()
  else:
    return "[nimo] No model available (offline)"

proc addMessage*(s: var Session, role: MessageRole, content: seq[ContentPart], parentId: string = ""): string =
  let msgId = "msg_" & $s.messages.len
  s.messages.add(Message(
    id: msgId, parentId: parentId, timestamp: nowStr(), role: role,
    content: content, stopReason: "stop"
  ))
  return msgId

proc addToolCall*(s: var Session, toolName: string, arguments: string, parentId: string): string =
  let msgId = "msg_" & $s.messages.len
  s.messages.add(Message(
    id: msgId, parentId: parentId, timestamp: nowStr(), role: mrAssistant,
    content: @[ContentPart(kind: ckToolCall, toolName: toolName, arguments: arguments)],
    stopReason: "toolUse"
  ))
  return msgId

proc addToolResult*(s: var Session, toolCallId: string, toolResult: string, isError: bool = false, parentId: string = ""): string =
  let msgId = "msg_" & $s.messages.len
  s.messages.add(Message(
    id: msgId, parentId: parentId, timestamp: nowStr(), role: mrToolResult,
    content: @[ContentPart(kind: ckToolResult, text: toolResult)],
    stopReason: "stop"
  ))
  return msgId

proc addText*(s: var Session, text: string, parentId: string, isThinking: bool = false): string =
  let msgId = "msg_" & $s.messages.len
  var content = newSeq[ContentPart]()
  if isThinking:
    content.add(ContentPart(kind: ckThinking, text: text))
  content.add(ContentPart(kind: ckText, text: text))
  s.messages.add(Message(
    id: msgId, parentId: parentId, timestamp: nowStr(),
    role: if parentId.len == 0: mrUser else: mrAssistant,
    content: content, stopReason: "stop"
  ))
  return msgId

proc registerTool*(s: var Session, name: string, handler: ToolHandler) =
  s.tools[name] = handler

proc executeTool*(s: var Session, toolCallId: string, toolName: string, arguments: string): string =
  if toolName notin s.tools:
    return "{\"error\": \"Tool not found: " & toolName & "\"}"
  try:
    return s.tools[toolName](arguments)
  except Exception as e:
    return "{\"error\": \"" & e.msg & "\"}"

proc roleToStr*(r: MessageRole): string =
  case r
  of mrUser: "user"
  of mrAssistant: "assistant"
  of mrToolResult: "toolResult"

proc kindToStr*(k: ContentKind): string =
  case k
  of ckText: "text"
  of ckThinking: "thinking"
  of ckToolCall: "toolCall"
  of ckToolResult: "toolResult"

proc saveSession*(s: Session, path: string) =
  let dir = parentDir(path)
  if dir.len > 0 and dir != ".":
    createDir(dir)
  let f = open(path, fmWrite)
  defer: f.close()

  var header = newJObject()
  header["type"] = % "session"
  header["version"] = %3
  header["id"] = %s.id
  header["timestamp"] = %s.timestamp
  header["cwd"] = %s.cwd
  f.writeLine($header)

  for msg in s.messages:
    var j = newJObject()
    j["type"] = % "message"
    j["id"] = %msg.id
    if msg.parentId.len > 0:
      j["parentId"] = %msg.parentId
    j["timestamp"] = %msg.timestamp
    j["role"] = %roleToStr(msg.role)

    var content = newJArray()
    for part in msg.content:
      var p = newJObject()
      p["type"] = %kindToStr(part.kind)
      if part.text.len > 0:
        p["text"] = %part.text
      if part.toolCallId.len > 0:
        p["toolCallId"] = %part.toolCallId
      if part.toolName.len > 0:
        p["toolName"] = %part.toolName
      if part.arguments.len > 0:
        p["arguments"] = %part.arguments
      content.add(p)
    j["content"] = content

    if msg.stopReason.len > 0:
      j["stopReason"] = %msg.stopReason

    f.writeLine($j)