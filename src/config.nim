## Global Configuration and Utility Helpers for RWKV Nim

import std/[os, strutils, json]

# The model-generation seam. It is the ONE pluggable boundary a session or
# engine calls to produce text. Unit tests mock precisely this (with precanned
# responses); everything else — session bookkeeping, plan execution, tool
# dispatch — runs for real against this seam.
type
  ## A streaming sink is called as soon as generated text is available. Real
  ## RWKV generation calls it once per decoded token; deterministic/offline
  ## generators may provide a single chunk.
  TokenSink* = proc(text: string)
  GenerateFn* = proc(prompt: string): string
  GenerateStreamFn* = proc(prompt: string, sink: TokenSink): string

const
  DefaultModelPath* = "models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin"
  DefaultVocabPath* = "rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt"
  DefaultPrompt* = "User: Hi!\n\nBot: Hello! How can I help you today?"
  DefaultGenLength* = 60
  DefaultTemp* = 0.7f
  DefaultTopP* = 0.7f
  DefaultChunkSize* = 16
  DefaultThreads* = 8
  DefaultGpuLayers* = -1  # -1 = derive from model shape + free VRAM (no magic number)
  DefaultConfigFile* = "nimo.json"
  DefaultMaxTokens* = 50              # Safe default to prevent loops; override in nimo.json
  DefaultQuantFormat* = ""          # "" = load model as-is; e.g. "Q4_K" -> raw->quantize->cache
  DefaultModelCacheDir* = ".nimo/model-cache"
  DefaultStateCacheDir* = ".nimo/state-cache"
  DefaultBakeContext* = false        # RFC 8000: bake systemPrompt state once, then resume it

# --- Backend selection (RFC 7500) ---
# Priority: config file > runtime flags > rwkv (compile-time default) > backend modules.
# "backend" chooses the rwkv.cpp runtime lib; "lib" overrides the lib path itself.
type
  RwkvBackendKind* = enum
    bkCpu = "cpu"
    bkCuda = "cuda"
    bkVulkan = "vulkan"

proc parseBackendKind*(s: string): RwkvBackendKind =
  ## Parses "cpu"/"cuda"/"vulkan" (also accepts "nvidia"). Raises ValueError otherwise.
  case s.toLowerAscii()
  of "cpu": bkCpu
  of "cuda", "nvidia": bkCuda
  of "vulkan", "amd": bkVulkan
  else: raise newException(ValueError, "unknown backend '" & s & "' (expected cpu|cuda|vulkan)")

type
  NimoConfig* = object
    modelPath*: string
    vocabPath*: string
    gpuLayers*: int      # <0: auto (model nLayer clamped by free VRAM); 0: CPU; >0: explicit cap
    backend*: RwkvBackendKind      # runtime backend: cpu | cuda | vulkan
    backendSet*: bool              # true when backend came from config/env (beats rwkv default)
    libPath*: string               # explicit librwkv.so path (overrides per-backend default)
    threads*: int
    temperature*: float32
    topP*: float32
    maxTokens*: int
    quantFormat*: string     # auto-quantize raw model into the model cache
    modelCacheDir*: string
    stateCacheDir*: string
    systemPrompt*: string    # fixed context baked into the state cache (RFC 8000)
    bakeContext*: bool       # resume baked state; bake on miss when true
    scriptReplies*: string   # L1 test seam: path to JSON array of scripted model
                             # replies (offline builds only) — deterministic CLI tests

proc defaultConfig*(): NimoConfig =
  NimoConfig(
    modelPath: DefaultModelPath,
    vocabPath: DefaultVocabPath,
    gpuLayers: DefaultGpuLayers,
    backend: bkCuda,
    backendSet: false,
    libPath: "",
    threads: DefaultThreads,
    temperature: DefaultTemp,
    topP: DefaultTopP,
    maxTokens: DefaultMaxTokens,
    quantFormat: DefaultQuantFormat,
    modelCacheDir: DefaultModelCacheDir,
    stateCacheDir: DefaultStateCacheDir,
    systemPrompt: "",
    bakeContext: DefaultBakeContext,
    scriptReplies: "",
  )

proc loadConfig*(path: string = DefaultConfigFile): NimoConfig =
  ## Loads nimo.json (if present), then env-var overrides on top.
  result = defaultConfig()
  if fileExists(path):
    try:
      let j = parseJson(readFile(path))
      if j.hasKey("model"):
        result.modelPath = j["model"].getStr(result.modelPath)
      if j.hasKey("vocab"):
        result.vocabPath = j["vocab"].getStr(result.vocabPath)
      if j.hasKey("gpuLayers"):
        result.gpuLayers = j["gpuLayers"].getInt(result.gpuLayers)
      if j.hasKey("backend"):
        try:
          result.backend = parseBackendKind(j["backend"].getStr())
          result.backendSet = true
        except ValueError:
          discard
      if j.hasKey("lib"):
        result.libPath = j["lib"].getStr(result.libPath)
      if j.hasKey("threads"):
        result.threads = j["threads"].getInt(result.threads)
      if j.hasKey("temperature"):
        result.temperature = j["temperature"].getFloat(result.temperature.float).float32
      if j.hasKey("topP"):
        result.topP = j["topP"].getFloat(result.topP.float).float32
      if j.hasKey("maxTokens"):
        result.maxTokens = j["maxTokens"].getInt(result.maxTokens)
      if j.hasKey("quant"):
        result.quantFormat = j["quant"].getStr(result.quantFormat)
      if j.hasKey("modelCacheDir"):
        result.modelCacheDir = j["modelCacheDir"].getStr(result.modelCacheDir)
      if j.hasKey("stateCacheDir"):
        result.stateCacheDir = j["stateCacheDir"].getStr(result.stateCacheDir)
      if j.hasKey("systemPrompt"):
        result.systemPrompt = j["systemPrompt"].getStr(result.systemPrompt)
      if j.hasKey("bakeContext"):
        result.bakeContext = j["bakeContext"].getBool(result.bakeContext)
    except JsonParsingError, ValueError:
      discard

proc resolveModelPath*(path: string): string =
  ## Automatically resolves .st / .pth / .safetensors model path candidates to matching .bin GGML model file.
  result = path
  if result.endsWith(".st") or result.endsWith(".pth") or result.endsWith(".safetensors"):
    let lastDot = result.rfind('.')
    let binCandidate = result[0 ..< lastDot] & ".bin"
    if fileExists(binCandidate):
      return binCandidate
