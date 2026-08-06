## RWKV Interactive Chat — CLI with session management
## Usage: nimo chat --backend cuda --model <path> [--device gpu-0]

import std/[os, strutils, strformat, terminal, options]
import cli, ./session_manager, ./config, ./tokenizer, ./rwkv, ./logger,
       ./rwkv/backend/cpu/cpu_backend, ./rwkv/backend/cuda/cuda_backend,
       ./rwkv/backend/vulkan/vulkan_backend

type
  ChatOpts = object
    device*: Option[string]
    backend*: Option[RwkvBackendKind]
    lib*: Option[string]
    modelPath*: string
    vocabPath*: string
    bakedStatePath*: string

proc checkBackendDeviceCompatibility(backend: RwkvBackendKind, device: string): string =
  ## Returns error message if backend/device combination is invalid.
  let dev = device.toLowerAscii()
  case backend
  of bkCpu:
    if dev != "cpu" and dev != "":
      return &"CPU backend requires --device cpu, got '{device}'"
  of bkCuda:
    if not dev.startsWith("gpu") and dev != "cuda":
      return &"CUDA backend requires --device gpu-* or 'cuda', got '{device}'"
  of bkVulkan:
    if not dev.startsWith("vulkan") and dev != "vulkan":
      return &"Vulkan backend requires --device vulkan-* or 'vulkan', got '{device}'"
  return ""

proc parseArgs(args: seq[string]): ChatOpts =
  var i = 0
  var opts = ChatOpts(
    modelPath: DefaultModelPath,
    vocabPath: DefaultVocabPath
  )

  while i < args.len:
    let arg = args[i]
    if arg == "--help" or arg == "-h":
      echo """nimo chat [OPTIONS] [MODEL] [VOCAB] [STATE]

Backend/Device selection:
  --device NAME     target device (e.g. gpu-0, cpu, vulkan-0)
  --backend CPU|CUDA|VULKAN   choose backend
  --lib PATH        explicit librwkv.so (overrides --backend)

Model:
  MODEL             model file path (default: """ & DefaultModelPath & """)
  VOCAB             vocab file path (default: """ & DefaultVocabPath & """)
  STATE             baked state file path (optional)

Examples:
  nimo chat --backend cuda --model ./models/model-q4k.bin
  nimo chat --device gpu-0 --backend cuda --model ./models/model-q4k.bin
"""
      quit(0)
    elif arg == "--device" and i + 1 < args.len:
      inc i
      opts.device = some(args[i])
    elif arg == "--backend" and i + 1 < args.len:
      inc i
      let s = args[i].strip().toLowerAscii()
      if s == "cpu": opts.backend = some(bkCpu)
      elif s == "cuda": opts.backend = some(bkCuda)
      elif s == "vulkan": opts.backend = some(bkVulkan)
      else:
        echo "Error: unknown backend '" & s & "' (expected cpu|cuda|vulkan)"
        quit(1)
    elif arg == "--lib" and i + 1 < args.len:
      inc i
      opts.lib = some(args[i])
    elif arg.startsWith("--"):
      echo "Error: unknown option '" & arg & "'"
      quit(1)
    else:
      # positional args: model, vocab, state
      if opts.modelPath == DefaultModelPath:
        opts.modelPath = arg
      elif opts.vocabPath == DefaultVocabPath:
        opts.vocabPath = arg
      elif opts.bakedStatePath.len == 0:
        opts.bakedStatePath = arg
      else:
        echo "Error: unexpected positional argument '" & arg & "'"
        quit(1)
    inc i

  return opts

proc main() =
  var args = newSeq[string]()
  for i in 1 .. paramCount():
    args.add(paramStr(i))
  let opts = parseArgs(args)

  let modelPath = resolveModelPath(opts.modelPath)
  let vocabPath = opts.vocabPath
  let bakedStatePath = opts.bakedStatePath

  logSessionStart("RWKV Chat", modelPath, vocabPath)
  printBanner "RWKV Interactive Chat"
  printConfig(modelPath, vocabPath)
  echo "Commands: /reset, /quit"
  echo ""

  if not fileExists(modelPath):
    printError &"Model not found: {modelPath}"
    return

  # Resolve backend
  var cfg = loadConfig()
  if opts.backend.isSome:
    cfg.backend = opts.backend.get
    cfg.backendSet = true
  if opts.lib.isSome: cfg.libPath = opts.lib.get

  let backend = selectBackend(cfg)
  echo "[backend] ", backend.name

  # Check device compatibility
  if opts.device.isSome:
    let device = opts.device.get
    let compatErr = checkBackendDeviceCompatibility(backend.kind, device)
    if compatErr.len > 0:
      printError compatErr
      quit(1)
    echo "[device] ", device

  # Bind backend
  try:
    bindBackend(backend.libPath)
  except RwkvException as e:
    printError &"Backend error: {e.msg}"
    echo ""
    echo "To run a different backend:"
    echo "  --backend cpu|cuda|vulkan"
    echo "  --lib <path to librwkv.so>"
    quit(1)

  var s = newSession(".")
  s.initModel(modelPath, vocabPath, backend.defaultGpuLayers)

  if bakedStatePath.len > 0 and fileExists(bakedStatePath):
    printWarn &"Loading baked state from '{bakedStatePath}'"
    s.state.loadState(bakedStatePath)
  else:
    let sysPrompt = "You are nimo.\n\nUser: hi\n\nBot: Hello! How can I help you?\n\nUser: what is your name?\n\nBot: I am nimo.\n\nUser:"
    let sysTokens = s.tok.encode(sysPrompt)
    if sysTokens.len > 0:
      discard s.model.evalSequenceInChunks(sysTokens, DefaultChunkSize, s.state, s.logits)

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
      s = newSession(".")
      s.initModel(modelPath, vocabPath, backend.defaultGpuLayers)
      let sysPrompt = "You are nimo.\n\nUser: hi\n\nBot: Hello! How can I help you?\n\nUser: what is your name?\n\nBot: I am nimo.\n\nUser:"
      let sysTokens = s.tok.encode(sysPrompt)
      if sysTokens.len > 0:
        discard s.model.evalSequenceInChunks(sysTokens, DefaultChunkSize, s.state, s.logits)
      continue

    stdout.write("Bot:  ")
    stdout.flushFile()
    let reply = s.generateTurnStream(inputLine, proc(token: string) =
      stdout.write(token)
      stdout.flushFile())
    echo ""
    logChatInteraction(inputLine, reply)

when isMainModule:
  main()
