## RWKV Text Generation — CLI with backend/device/quant selection
## Usage: nimo generate --device gpu-0 --backend cuda --quant q4k --model <path> --prompt "Hello"

import std/[os, strutils, strformat, times, options]
import cli, ./session_manager, ./config, ./tokenizer, ./rwkv, ./sampling, ./logger, ./macros,
       ./rwkv/model/header, ./rwkv/backend/cuda/cuda_backend,
       ./rwkv/backend/vulkan/vulkan_backend, ./lock

type
  GenOpts = object
    device*: Option[string]
    backend*: Option[RwkvBackendKind]
    lib*: Option[string]
    quant*: Option[string]
    maxTokens*: int
    temperature*: float32
    topp*: float32
    prompt*: string
    modelPath*: string
    vocabPath*: string

proc parseArgs(args: seq[string]): GenOpts =
  var i = 0
  var opts = GenOpts(
    maxTokens: DefaultGenLength,
    temperature: DefaultTemp,
    topp: DefaultTopP,
    modelPath: DefaultModelPath,
    vocabPath: DefaultVocabPath
  )

  while i < args.len:
    let arg = args[i]
    if arg == "--help" or arg == "-h":
      echo """nimo generate [OPTIONS] --prompt "PROMPT"

Backend/Device selection:
  --device NAME     target device (e.g. gpu-0, vulkan-0)
  --backend CUDA|VULKAN   choose backend
  --lib PATH        explicit librwkv.so (overrides --backend)

Model/Quant:
  --model PATH      model file path
  --quant FORMAT    target quant (Q4_0, Q4_K, Q5_0, Q5_K, Q6_K, Q8_0)
                    must match model's actual quant

Generation:
  --max-length N    max output tokens (default: 60)
  --temperature F   sampling temperature (default: 0.7)
  --topp F          top-p (default: 0.7)

Examples:
  nimo generate --backend cuda --model ./models/model-q4k.bin --prompt "Hello"
  nimo generate --device gpu-0 --backend cuda --quant q4k --model ./models/model.bin --prompt "Hi"
"""
      quit(0)
    elif arg == "--device" and i + 1 < args.len:
      inc i
      opts.device = some(args[i])
    elif arg == "--backend" and i + 1 < args.len:
      inc i
      let s = args[i].strip().toLowerAscii()
      if s == "cuda": opts.backend = some(bkCuda)
      elif s == "vulkan": opts.backend = some(bkVulkan)
      else:
        echo "Error: unknown backend '" & s & "' (expected cuda|vulkan)"
        quit(1)
    elif arg == "--lib" and i + 1 < args.len:
      inc i
      opts.lib = some(args[i])
    elif arg == "--quant" and i + 1 < args.len:
      inc i
      opts.quant = some(args[i].strip().toUpperAscii())
    elif arg == "--model" and i + 1 < args.len:
      inc i
      opts.modelPath = args[i]
    elif arg == "--max-length" and i + 1 < args.len:
      inc i
      opts.maxTokens = parseInt(args[i])
    elif arg == "--temperature" and i + 1 < args.len:
      inc i
      opts.temperature = parseFloat(args[i])
    elif arg == "--topp" and i + 1 < args.len:
      inc i
      opts.topp = parseFloat(args[i])
    elif arg == "--prompt" and i + 1 < args.len:
      inc i
      # Collect all remaining args as prompt (handles multi-word from shell splitting)
      opts.prompt = args[i]
      inc i
      while i < args.len and not args[i].startsWith("--"):
        opts.prompt.add(" " & args[i])
        inc i
      dec i  # step back one so the outer loop increments correctly
    elif arg.startsWith("--"):
      echo "Error: unknown option '" & arg & "'"
      quit(1)
    else:
      # positional
      if opts.prompt.len == 0:
        opts.prompt = arg
      elif opts.modelPath == DefaultModelPath:
        opts.modelPath = arg
      elif opts.vocabPath == DefaultVocabPath:
        opts.vocabPath = arg
      else:
        echo "Error: unexpected positional argument '" & arg & "'"
        quit(1)
    inc i

  if opts.prompt.len == 0:
    echo "Error: --prompt is required"
    quit(1)
  return opts

proc checkBackendDeviceCompatibility(backend: RwkvBackendKind, device: string): string =
  ## Returns error message if backend/device combination is invalid.
  let dev = device.toLowerAscii()
  case backend
  of bkCuda:
    if not dev.startsWith("gpu") and dev != "cuda":
      return &"CUDA backend requires --device gpu-* or 'cuda', got '{device}'"
  of bkVulkan:
    if not dev.startsWith("vulkan") and dev != "vulkan":
      return &"Vulkan backend requires --device vulkan-* or 'vulkan', got '{device}'"
  return ""

proc checkModelQuant(modelPath: string, requestedQuant: string): string =
  ## Returns error message if model's actual quant doesn't match requested.
  if not fileExists(modelPath):
    return &"Model not found: {modelPath}"

  let h = readModelHeader(modelPath)
  if not isValidHeader(h):
    return &"Invalid model header in: {modelPath}"

  if not isQuantized(h):
    let fpType = if h.dataType == DtypeFP32: "32" else: "16"
    return &"Model is raw (FP{fpType}), but --quant {requestedQuant} was requested. Convert first with: nimo quantize"

  # Map header dtype to quant name
  var actualQuant = ""
  case h.dataType
  of DtypeQ4_0: actualQuant = "Q4_0"
  of DtypeQ4_1: actualQuant = "Q4_1"
  of DtypeIQ4_NL: actualQuant = "IQ4_NL"
  of DtypeQ4_K: actualQuant = "Q4_K"
  of DtypeQ5_0: actualQuant = "Q5_0"
  of DtypeQ5_1: actualQuant = "Q5_1"
  of DtypeQ5_K: actualQuant = "Q5_K"
  of DtypeQ6_K: actualQuant = "Q6_K"
  of DtypeQ8_0: actualQuant = "Q8_0"
  of DtypeQ8_K: actualQuant = "Q8_K"
  else: actualQuant = "UNKNOWN"

  let requestedUpper = requestedQuant.toUpperAscii()
  if actualQuant != requestedUpper:
    return &"Model quant is {actualQuant}, but --quant {requestedQuant} was requested"

  return ""

proc generateCmd(args: seq[string]) =
  let opts = parseArgs(args)

  printBanner "nimo generate"

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

  # Check model quant match
  let modelPath = resolveModelPath(opts.modelPath)
  if opts.quant.isSome:
    let quantErr = checkModelQuant(modelPath, opts.quant.get)
    if quantErr.len > 0:
      printError quantErr
      quit(1)
    echo "[quant] ", opts.quant.get

  echo "[model] ", modelPath
  echo "[prompt] ", opts.prompt
  echo SepThin

  # Bind backend
  try:
    bindBackend(backend.libPath)
  except RwkvException as e:
    printError &"Backend error: {e.msg}"
    echo ""
    echo "To run a different backend:"
    echo "  --backend cuda|vulkan"
    echo "  --lib <path to librwkv.so>"
    quit(1)

  # Load model (with lock to prevent OOM)
  var s = newSession(".")
  if not acquireModelLock():
    printError "[gpu] ERROR: Another process is loading the model. Waiting..."
    printError "Try again in a moment, or run: pkill -f 'nimo|harness'"
    quit(1)
  try:
    s.initModel(modelPath, cfg.vocabPath, backend.defaultGpuLayers)
  except Exception as e:
    releaseModelLock()
    printError &"Failed to load model: {e.msg}"
    quit(1)
  defer: releaseModelLock()

  var promptTokens = s.tok.encode(opts.prompt)
  if promptTokens.len == 0:
    printError "Empty prompt."
    quit(1)

  var elapsed = 0.0
  var fullGenerated = ""
  var stepCount = 0

  timeBlock(elapsed):
    benchmarkStep("prompt_eval"):
      checkOk(s.model.evalSequenceInChunks(promptTokens, DefaultChunkSize, s.state, s.logits),
              "Failed to evaluate prompt")

    stdout.write(opts.prompt)
    stdout.flushFile()

    for step in 0 ..< opts.maxTokens:
      let token = sampleLogits(s.logits, temperature = opts.temperature, topP = opts.topp, rng = s.rng)
      if token == 0: break
      let tokenStr = s.tok.decodeToken(token.uint32)
      fullGenerated.add(tokenStr)
      inc stepCount
      stdout.write(tokenStr)
      stdout.flushFile()
      if not s.model.eval(token.uint32, s.state, s.logits): break

  echo ""
  echo SepThin
  let msPerTok = if stepCount > 0: elapsed / float(stepCount) * 1000.0 else: 0.0
  printSuccess &"Generated {stepCount} tokens in {elapsed:.3f}s ({msPerTok:.1f} ms/token)"
  logGenerationRun(opts.prompt, fullGenerated, elapsed, stepCount)

when isMainModule:
  var args = newSeq[string]()
  for i in 1 .. paramCount():
    args.add(paramStr(i))
  generateCmd(args)
