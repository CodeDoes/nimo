## Session Manager for NIMO Harness
## Manages messages, tools, and JSONL logging.
##
## Build with `-d:harnessOffline` to strip the RWKV model backend, letting the
## harness (and unit tests) run without rwkv.cpp / a GPU model. Generation is
## injected as a parameter (`generate: GenerateFn`); pass `nil` to use the real
## model on this session (offline builds always get the placeholder).

import std/[json, times, os, tables, strutils]
import ./config
when not defined(harnessOffline):
  import std/[random]
  import ./rwkv, ./tokenizer, ./sampling, ./macros, ./rwkv/state/cache

type
  ContentKind* = enum
    ckText, ckThinking, ckToolCall, ckToolResult, ckPlan, ckReport

  ContentPart* = object
    kind*: ContentKind
    text*: string
    toolCallId*: string
    toolName*: string
    arguments*: string
    thinkingSignature*: string
    reportKind*: string      # planner | step | finished (RFC 1000 report)

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

proc generateTurnStream*(s: var Session, userMsg: string, sink: TokenSink = nil,
                         generate: GenerateFn = nil,
                         temp: float32 = DefaultTemp, topP: float32 = DefaultTopP,
                         maxTokens: int = 200): string =
  ## Generates a reply and immediately forwards each decoded token to `sink`.
  ## The returned text keeps buffered callers and offline tests compatible.
  if generate != nil:
    result = generate(userMsg)
    if sink != nil and result.len > 0:
      sink(result) # scripted generators have no token boundary to expose
    return
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
      if sink != nil:
        sink(tokenStr)
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
    result = "[nimo] No model available (offline)"
    if sink != nil:
      sink(result)

proc generateTurn*(s: var Session, userMsg: string, generate: GenerateFn = nil,
                   temp: float32 = DefaultTemp, topP: float32 = DefaultTopP,
                   maxTokens: int = 200): string =
  ## Compatibility wrapper for callers that need a complete reply.
  s.generateTurnStream(userMsg, nil, generate, temp, topP, maxTokens)

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

proc addPlan*(s: var Session, planJson: JsonNode, parentId: string = ""): string =
  ## Records a `plan` node in the history (RFC 1000) — the compiled program.
  let msgId = "msg_" & $s.messages.len
  s.messages.add(Message(
    id: msgId, parentId: parentId, timestamp: nowStr(), role: mrAssistant,
    content: @[ContentPart(kind: ckPlan, text: $planJson)],
    stopReason: "toolUse"
  ))
  return msgId

proc addReport*(s: var Session, reportKind: string, text: string, parentId: string = ""): string =
  ## Records a `report` event (RFC 1000): kind is planner | step | finished.
  let msgId = "msg_" & $s.messages.len
  s.messages.add(Message(
    id: msgId, parentId: parentId, timestamp: nowStr(), role: mrAssistant,
    content: @[ContentPart(kind: ckReport, reportKind: reportKind, text: text)],
    stopReason: "stop"
  ))
  return msgId

proc addModelEvent*(s: var Session, modelPath: string, sig: string = "") =
  ## Records a `model` bind/switch event (RFC 1000).
  let msgId = "msg_" & $s.messages.len
  s.messages.add(Message(
    id: msgId, parentId: "", timestamp: nowStr(), role: mrAssistant,
    content: @[ContentPart(kind: ckText, text: "model bound: " & modelPath &
                        (if sig.len > 0: " (" & sig & ")" else: ""))],
    stopReason: "stop"
  ))

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
  of ckPlan: "plan"
  of ckReport: "report"

proc messageToJson*(msg: Message): JsonNode =
  ## Serializes a Message to a JsonNode.
  result = newJObject()
  result["type"] = % "message"
  result["id"] = %msg.id
  if msg.parentId.len > 0:
    result["parentId"] = %msg.parentId
  result["timestamp"] = %msg.timestamp
  result["role"] = %roleToStr(msg.role)

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
    if part.reportKind.len > 0:
      p["reportKind"] = %part.reportKind
    content.add(p)
  result["content"] = content

  if msg.stopReason.len > 0:
    result["stopReason"] = %msg.stopReason

proc parseRole*(s: string): MessageRole =
  case s.toLowerAscii()
  of "user": mrUser
  of "assistant": mrAssistant
  of "toolresult", "tool_result": mrToolResult
  else: mrUser

proc parseKind*(s: string): ContentKind =
  case s.toLowerAscii()
  of "text": ckText
  of "thinking": ckThinking
  of "toolcall", "tool_call": ckToolCall
  of "toolresult", "tool_result": ckToolResult
  of "plan": ckPlan
  of "report": ckReport
  else: ckText

proc messageFromJson*(j: JsonNode): Message =
  ## Deserializes a Message from a JsonNode.
  result.id = j["id"].getStr("")
  if "parentId" in j:
    result.parentId = j["parentId"].getStr("")
  result.timestamp = j["timestamp"].getStr("")
  result.role = parseRole(j["role"].getStr("user"))

  result.content = @[]
  if "content" in j and j["content"].kind == JArray:
    for pj in j["content"]:
      var part: ContentPart
      part.kind = parseKind(pj["type"].getStr("text"))
      if "text" in pj: part.text = pj["text"].getStr("")
      if "toolCallId" in pj: part.toolCallId = pj["toolCallId"].getStr("")
      if "toolName" in pj: part.toolName = pj["toolName"].getStr("")
      if "arguments" in pj: part.arguments = pj["arguments"].getStr("")
      if "reportKind" in pj: part.reportKind = pj["reportKind"].getStr("")
      result.content.add(part)

  if "stopReason" in j:
    result.stopReason = j["stopReason"].getStr("")

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
    f.writeLine($(messageToJson(msg)))

proc loadSession*(path: string): Session =
  ## Loads a Session from a JSONL file. Returns nil if file not found or invalid.
  if not fileExists(path):
    return nil
  try:
    let lines = readFile(path).splitLines()
    if lines.len == 0 or lines[0].strip().len == 0:
      return nil

    let headerJ = parseJson(lines[0])
    if headerJ.kind != JObject or headerJ["type"].getStr("") != "session":
      return nil

    result = Session.new()
    result.id = headerJ["id"].getStr("")
    result.timestamp = headerJ["timestamp"].getStr("")
    result.cwd = headerJ["cwd"].getStr(".")
    result.activeBranch = 0
    result.tools = initTable[string, ToolHandler]()
    result.messages = @[]

    for i in 1 ..< lines.len:
      let line = lines[i].strip()
      if line.len == 0: continue
      let j = parseJson(line)
      if j.kind == JObject and j["type"].getStr("") == "message":
        result.messages.add(messageFromJson(j))
  except CatchableError:
    return nil