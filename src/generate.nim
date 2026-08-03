## RWKV Text Generation — CLI with backend selection
## Usage: nimo generate [OPTIONS] PROMPT [MODEL] [VOCAB]
##   nimo generate --backend cpu "Hello world"
##   nimo generate --backend cuda --max-length 20 "Continue"
##   nimo generate --backend vulkan --lib ./build/librwkv.so "Summarize"

import std/[os, strutils, strformat, times, options]
import cli, ./session, ./config, ./tokenizer, ./rwkv, ./sampling, ./logger, ./macros

type GenOpts = object
  backend*: Option[RwkvBackendKind]
  lib*: Option[string]
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
      echo """nimo generate [OPTIONS] PROMPT [MODEL] [VOCAB]

Backend selection (single controlled path: config > env > runtime > modules):
  --backend CPU|CUDA|VULKAN   choose backend
  --lib PATH                  explicit librwkv.so (overrides --backend)

Generation:
  --max-length N              max output tokens (default: 60)
  --temperature F             sampling temperature (default: 0.7)
  --topp F                    top-p (default: 0.7)

Examples:
  nimo generate --backend cpu "Hello world"
  nimo generate --backend cuda --max-length 20 "Continue the story"
  nimo generate --backend vulkan "Summarize this"
"""
      quit(0)
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
    elif arg == "--max-length" and i + 1 < args.len:
      inc i
      opts.maxTokens = parseInt(args[i])
    elif arg == "--temperature" and i + 1 < args.len:
      inc i
      opts.temperature = parseFloat(args[i])
    elif arg == "--topp" and i + 1 < args.len:
      inc i
      opts.topp = parseFloat(args[i])
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
    echo "Error: PROMPT is required"
    quit(1)
  return opts

proc generateCmd(args: seq[string]) =
  let opts = parseArgs(args)

  printBanner "nimo generate"
  echo "Prompt:   ", opts.prompt
  echo "Max len:  ", opts.maxTokens, " tokens"
  echo SepThin

  # Load config, apply runtime overrides (config > env > explicit args).
  var cfg = loadConfig()
  if opts.backend.isSome:
    cfg.backend = opts.backend.get
    cfg.backendSet = true   # runtime flag beats compile-time default
  if opts.lib.isSome: cfg.libPath = opts.lib.get

  # Single controlled path: select backend, bind lib.
  let backend = selectBackend(cfg)
  echo "[backend] ", backend.name, "  lib=", backend.libPath
  # Bind the selected backend. If the lib is missing or wrong, bindBackend
  # raises RwkvException — catch it and print a clean error instead of
  # silently falling back to a different backend.
  try:
    bindBackend(backend.libPath)
  except RwkvException as e:
    printError &"Backend error: {e.msg}"
    echo ""
    echo "To run a different backend:"
    echo "  --backend cpu|cuda|vulkan"
    echo "  --lib <path to librwkv.so>"
    quit(1)

  let modelPath = resolveModelPath(opts.modelPath)
  if not fileExists(modelPath):
    printError &"Model not found: {modelPath}"
    quit(1)

  var s = initSession(modelPath, cfg.vocabPath, backend.defaultGpuLayers)

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
  # Standalone: read from real paramCount/paramStr
  var args = newSeq[string]()
  for i in 1 .. paramCount():
    args.add(paramStr(i))
  generateCmd(args)
