## Global Configuration and Utility Helpers for RWKV Nim

import std/[os, strutils, json]

const
  DefaultModelPath* = "models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin"
  DefaultVocabPath* = "rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt"
  DefaultPrompt* = "User: Hi!\n\nBot: Hello! How can I help you today?"
  DefaultGenLength* = 60
  DefaultTemp* = 0.7f
  DefaultTopP* = 0.7f
  DefaultChunkSize* = 16
  DefaultThreads* = 8
  DefaultGpuLayers* = 99  # Offload all layers to GPU VRAM by default
  DefaultConfigFile* = "nimo.json"
  DefaultMaxTokens* = 200
  DefaultQuantFormat* = ""          # "" = load model as-is; e.g. "Q4_K" -> raw->quantize->cache
  DefaultModelCacheDir* = ".nimo/model-cache"
  DefaultStateCacheDir* = ".nimo/state-cache"
  DefaultBakeContext* = false        # RFC 8000: bake systemPrompt state once, then resume it

# --- Backend selection (RFC 7500) ---
# Priority: config file > env vars > rwkv (compile-time default) > backend modules.
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
    gpuLayers*: int
    allowCpuFallback*: bool  # run on CPU if the GPU is unusable
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

proc defaultConfig*(): NimoConfig =
  NimoConfig(
    modelPath: DefaultModelPath,
    vocabPath: DefaultVocabPath,
    gpuLayers: DefaultGpuLayers,
    allowCpuFallback: false,  # GPU required by default; opt-in to CPU
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
      if j.hasKey("allowCpuFallback"):
        result.allowCpuFallback = j["allowCpuFallback"].getBool(result.allowCpuFallback)
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

  let envModel = getEnv("NIMO_MODEL", "")
  if envModel.len > 0:
    result.modelPath = envModel
  let envVocab = getEnv("NIMO_VOCAB", "")
  if envVocab.len > 0:
    result.vocabPath = envVocab
  if getEnv("NIMO_ALLOW_CPU_FALLBACK", "") in ["1", "true", "yes"]:
    result.allowCpuFallback = true
  let envBackend = getEnv("NIMO_BACKEND", "")
  if envBackend.len > 0:
    try:
      result.backend = parseBackendKind(envBackend)
      result.backendSet = true
    except ValueError:
      discard
  let envLib = getEnv("NIMO_LIB", "")
  if envLib.len > 0:
    result.libPath = envLib
  let envLayers = getEnv("NIMO_GPU_LAYERS", "")
  if envLayers.len > 0:
    try:
      result.gpuLayers = parseInt(envLayers)
    except ValueError:
      discard
  let envQuant = getEnv("NIMO_QUANT", "")
  if envQuant.len > 0:
    result.quantFormat = envQuant
  let envMaxTokens = getEnv("NIMO_MAX_TOKENS", "")
  if envMaxTokens.len > 0:
    try:
      result.maxTokens = parseInt(envMaxTokens)
    except ValueError:
      discard
  if getEnv("NIMO_BAKE_CONTEXT", "") in ["1", "true", "yes"]:
    result.bakeContext = true
  let envSys = getEnv("NIMO_SYSTEM_PROMPT", "")
  if envSys.len > 0:
    result.systemPrompt = envSys
  let envModelCache = getEnv("NIMO_MODEL_CACHE", "")
  if envModelCache.len > 0:
    result.modelCacheDir = envModelCache
  let envStateCache = getEnv("NIMO_STATE_CACHE", "")
  if envStateCache.len > 0:
    result.stateCacheDir = envStateCache

proc resolveModelPath*(path: string): string =
  ## Automatically resolves .st / .pth / .safetensors model path candidates to matching .bin GGML model file.
  result = path
  if result.endsWith(".st") or result.endsWith(".pth") or result.endsWith(".safetensors"):
    let lastDot = result.rfind('.')
    let binCandidate = result[0 ..< lastDot] & ".bin"
    if fileExists(binCandidate):
      return binCandidate
