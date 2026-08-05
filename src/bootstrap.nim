## bootstrap.nim — the ONE canonical way to get a configured Session.
##
## Principle C (≤6 concepts): `bootstrapSession(cfg)` is how you obtain a
## Session. It folds the model bootstrapping that was triplicated across
## harness/chat/generate into a single controlled place:
##   bind backend → GPU policy → quant cache → init model
## Offline-safe (with `-d:harnessOffline` it returns the stub-generator session
## and never touches the model/GPU).

import std/[os]
import ./config, ./session_manager

when not defined(harnessOffline):
  import std/[strutils]
  import ./rwkv, ./gpu, ./rwkv/quant/cache,
         ./rwkv/backend/cpu/cpu_backend,
         ./rwkv/backend/cuda/cuda_backend,
         ./rwkv/backend/vulkan/vulkan_backend

type
  BootstrapResult* = object
    ok*: bool
    session*: Session
    generate*: GenerateFn   # model-generation seam; nil = use session's real model
    lines*: seq[string]     # informational / diagnostic lines for the caller to echo

when not defined(harnessOffline):
  proc bootstrapOnline(cfg: NimoConfig, cwd: string): BootstrapResult  # defined below

proc bootstrapSession*(cfg: NimoConfig, cwd: string = getCurrentDir()): BootstrapResult =
  ## Builds a Session + its generator from config, the one canonical way. On
  ## failure `ok` is false and `lines` holds the diagnostics (and fix
  ## suggestions) to show. The generator is returned alongside the session —
  ## it is injected at call sites, never stored on the session.

  when defined(harnessOffline):
    result.ok = true
    result.session = newSession(cwd)
    result.generate = proc(userMsg: string): string = "[nimo offline] no model"
    result.lines.add "[nimo] offline mode: no model loaded; generation returns placeholder text"
    return
  else:
    result = bootstrapOnline(cfg, cwd)

when not defined(harnessOffline):
  proc bootstrapOnline(cfg: NimoConfig, cwd: string): BootstrapResult =
    ## The real-model bootstrap (only compiled in online builds).
    var s = newSession(cwd)

    # 1. Backend selection (RFC 7500): config > runtime flags > rwkv default >
    #    backend libs. selectBackend is the single controlled switch point.
    let backend = selectBackend(cfg)
    try:
      bindBackend(backend.libPath)
    except RwkvException as e:
      result.ok = false
      result.lines.add "Backend error: " & e.msg
      result.lines.add "To run a different backend, set backend/lib in nimo.json or:"
      result.lines.add "  --backend cpu|cuda|vulkan --lib <librwkv.so path>"
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
        result.lines.add "Options:"
        result.lines.add "  1. Fix the GPU (see the [gpu] message above), or"
        result.lines.add "  2. Use a non-CUDA backend:"
        result.lines.add "       nimo.json -> { \"backend\": \"cpu\" }"
        result.lines.add "       or       -> --backend cpu"
        return
      result.lines.add "[gpu] using " & $layers & " GPU layer(s)."
      let err = checkCudaLoad(backend, modelToLoad, "default", layers)
      if err.len > 0:
        result.ok = false
        result.lines.add "CUDA load check failed: " & err
        return
    of bkCpu:
      layers = 0
      result.lines.add "[gpu] CPU backend: gpuLayers=0."
      let err = checkCpuLoad(backend, modelToLoad, "default")
      if err.len > 0:
        result.ok = false
        result.lines.add "CPU load check failed: " & err
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
                  cfg.systemPrompt, cfg.stateCacheDir, cfg.bakeContext)
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
        result.lines.add "Then retry. Or use a different backend:"
        result.lines.add "  --backend cpu"
      return

    result.ok = true
    result.session = s
