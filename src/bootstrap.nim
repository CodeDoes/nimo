## bootstrap.nim — the ONE canonical way to get a configured Session.
##
## Principle C (≤6 concepts): `bootstrapSession(cfg)` is how you obtain a
## Session. It folds the model bootstrapping that was triplicated across
## harness/chat/generate into a single controlled place:
##   bind backend → GPU policy → quant cache → init model
##
## NO compile-time model/stub fork: the binary is the same everywhere. At
## runtime it asks "is a backend + model actually usable here?" and either
## loads the real model (cuda/vulkan) or degrades to a clearly-labeled
## deterministic stub (no cuda, no vulkan, no model file — that's fine).

import std/[os, json, strutils]
import ./config, ./session_manager
import ./lock
import ./rwkv, ./gpu, ./rwkv/quant/cache,
       ./rwkv/backend/cuda/cuda_backend,
       ./rwkv/backend/vulkan/vulkan_backend

type
  BootstrapResult* = object
    ok*: bool
    session*: Session
    generate*: GenerateFn   # model-generation seam; nil = use session's real model
    lines*: seq[string]     # informational / diagnostic lines for the caller to echo
    stub*: bool             # true = degraded to the deterministic stub (no real model)

proc canRunRealModel(cfg: NimoConfig): bool =
  ## Runtime capability check — the old `-d:harnessOffline` fork, now decided
  ## by what this machine actually has. Both must hold to go real:
  ##   1. a model file exists
  ##   2. a backend librwkv can be dlopen'd (cuda/vulkan)
  ## If either is missing we degrade to the stub — never a hard failure.
  let modelPath = if isAbsolute(cfg.modelPath): cfg.modelPath
                  else: getCurrentDir() / cfg.modelPath
  if not fileExists(modelPath): return false
  var backendOk = false
  try:
    let backend = selectBackend(cfg)
    backendOk = fileExists(backend.libPath)
  except CatchableError:
    backendOk = false
  return backendOk

proc stubSession(cfg: NimoConfig, cwd: string): BootstrapResult =
  ## The deterministic stub: same session shape, generation replaced by a
  ## scripted/placeholder function. Selected at RUNTIME when this machine has
  ## no usable backend + model (remote agents, CI, bare-metal without CUDA).
  result.ok = true
  result.stub = true
  result.session = newSession(cwd)
  if cfg.scriptReplies.len > 0 and fileExists(cfg.scriptReplies):
    # L1 test seam: drive the CLI with a scripted model so the whole
    # user -> tool-call -> dispatch -> file-write -> answer path is testable
    # deterministically at the binary level (no rwkv.cpp, no GPU).
    var idx = 0
    var replies: seq[string]
    try:
      let j = parseJson(readFile(cfg.scriptReplies))
      if j.kind == JArray:
        for n in j:
          if n.kind == JString:
            replies.add(n.str)
    except CatchableError:
      discard
    result.generate = proc(userMsg: string): string =
      if idx < replies.len:
        result = replies[idx]
        inc idx
      else:
        result = "[stub] no more scripted replies"
    result.lines.add "[stub] scripted model: " & $replies.len & " replies from " & cfg.scriptReplies
  else:
    result.generate = proc(userMsg: string): string = "[stub] no model"
    result.lines.add "[stub] no usable backend+model here; generation returns placeholder text"

proc bootstrapOnline(cfg: NimoConfig, cwd: string): BootstrapResult =
  ## The real-model bootstrap. Errors hard ONLY when the machine looked
  ## capable (model file + backend lib present) but something is actually
  ## broken (GPU unusable, backend load failure) — that deserves a real error,
  ## not a silent stub.
  
  # Acquire model load lock
  if not acquireModelLock():
    result.ok = false
    result.lines.add "[gpu] ERROR: Another process is loading the model. Waiting..."
    result.lines.add "Try again in a moment, or run: pkill -f 'nimo|harness'"
    return
  
  var s = newSession(cwd)
  defer: releaseModelLock()

  # 1. Backend selection (RFC 7500): config > runtime flags > rwkv default >
  #    backend libs. selectBackend is the single controlled switch point.
  let backend = selectBackend(cfg)
  try:
    bindBackend(backend.libPath)
  except RwkvException as e:
    result.ok = false
    result.lines.add "Backend error: " & e.msg
    result.lines.add "To run a different backend, set backend/lib in nimo.json or:"
    result.lines.add "  --backend cuda|vulkan --lib <librwkv.so path>"
    return
  result.lines.add "[backend] " & backend.name & "  lib=" & backend.libPath

  # 2. raw -> quantize -> cache: resolve the model actually loaded.
  var modelToLoad = cfg.modelPath
  if cfg.quantFormat.len > 0 and fileExists(cfg.modelPath):
    let mc = initModelCache(cfg.modelCacheDir)
    let (p, cached) = mc.ensureQuantized(cfg.modelPath, cfg.quantFormat)
    modelToLoad = p
    if not cached:
      result.lines.add "[model] quantized " & cfg.modelPath & " -> " & p
    elif p != cfg.modelPath:
      result.lines.add "[model] using cached " & cfg.quantFormat & ": " & p

  # 3. GPU policy: fail explicitly (with a clean diagnostic) before loading
  #    if the desired configuration can't work — never crash mid-init.
  var layers = cfg.gpuLayers
  case backend.kind
  of bkCuda:
    let gpu = gpuProbe()
    result.lines.add "[gpu] " & gpu.describe()
    let gpuDecision = decideGpu(gpu, cfg.gpuLayers)
    if gpuDecision.decision == gdBlocked:
      result.ok = false
      result.lines.add "Cannot start: the GPU is unusable."
      result.lines.add "Fix the GPU and retry:"
      result.lines.add "  reboot, or: sudo modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia && sudo modprobe nvidia"
      return
    # Derive offload from the model's own shape (header nLayer), clamped to
    # free VRAM — there is no hardcoded default layer count.
    if layers < 0:
      layers = resolveGpuLayers(modelToLoad, -1)
      if layers < 0:
        result.ok = false
        result.lines.add "Cannot determine model layer count (unreadable header): " & modelToLoad
        return
    result.lines.add "[gpu] using " & $layers & " GPU layer(s)."
    let err = checkCudaLoad(backend, modelToLoad, "default", layers)
    if err.len > 0:
      result.ok = false
      result.lines.add "CUDA load check failed: " & err
      return
  of bkVulkan:
    result.lines.add "[gpu] Vulkan backend: using " & $layers & " GPU layer(s)."
    let err = checkVulkanLoad(backend, modelToLoad, "default", layers)
    if err.len > 0:
      result.ok = false
      result.lines.add "Vulkan load check failed: " & err
      return

  # 4. Load the model (RFC 8000 state bake happens inside initModel).
  try:
    s.initModel(modelToLoad, cfg.vocabPath, layers,
                cfg.systemPrompt, cfg.stateCacheDir, cfg.bakeContext, cfg.seed)
    result.lines.add "[model] loaded."
    if cfg.bakeContext and cfg.systemPrompt.len > 0:
      result.lines.add "[model] cached state for system prompt (" & cfg.stateCacheDir & ")."
  except Exception as e:
    result.ok = false
    result.lines.add "Failed to load model: " & e.msg
    let upper = e.msg.toUpperAscii()
    if upper.contains("CUDA") or upper.contains("GPU") or upper.contains("DEVICE"):
      result.lines.add "This looks like a GPU/CUDA init failure. The driver may report \"GPU requires reset\":"
      result.lines.add "  reboot, or: sudo modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia && sudo modprobe nvidia"
      result.lines.add "Then retry."
    return

  result.ok = true
  result.session = s

proc bootstrapSession*(cfg: NimoConfig, cwd: string = getCurrentDir()): BootstrapResult =
  ## THE one canonical way to get a configured Session. At runtime it decides
  ## (not the compiler!) whether this machine can run a real model:
  ##   -> model file + usable backend (cuda/vulkan) present  : load the model
  ##   -> otherwise                                          : clearly-labeled stub
  if canRunRealModel(cfg):
    result = bootstrapOnline(cfg, cwd)
  else:
    result = stubSession(cfg, cwd)
