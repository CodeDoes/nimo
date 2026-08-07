## Nim wrapper for rwkv.cpp
## High-performance C/C++ implementation of RWKV language model inference.
##
## This is the BACKEND DISPATCHER (RFC 7500): it binds the rwkv.cpp C API at
## runtime to whichever backend librwkv.so is selected, in priority order
##   config file > runtime flags > rwkv (compile-time default) > backend modules.
## Backend providers live in rwkv_cuda / rwkv_vulkan; each only
## knows its own lib. The single controlled switch point is selectBackend() +
## bindBackend(path) — after that, every call below goes through the bound lib.

import std/[macros, strformat, dynlib]
when defined(linux):
  import posix
import ./config
import ./rwkv/backend/types, ./rwkv/backend/cuda/cuda_backend, ./rwkv/backend/vulkan/vulkan_backend

when defined(linux):
  {.passL: "-lstdc++ -fopenmp -Wl,-rpath,/usr/lib/x86_64-linux-gnu -Wl,-rpath,/run/opengl-driver/lib -Wl,-rpath,$ORIGIN/rwkv.cpp -Wl,-rpath,$ORIGIN/rwkv.cpp/ggml/src -Wl,-rpath,rwkv.cpp -Wl,-rpath,rwkv.cpp/ggml/src".}

# Compile-time default backend (rwkv-level authority). Override with e.g.
#   nim c -d:rwkvDefaultBackend=vulkan ...
const DefaultBackendKind* {.strdefine.} = "cuda"

const
  RWKV_FILE_MAGIC* = 0x67676d66
  RWKV_FILE_VERSION_0* = 100
  RWKV_FILE_VERSION_1* = 101
  RWKV_FILE_VERSION_MIN* = RWKV_FILE_VERSION_0
  RWKV_FILE_VERSION_MAX* = RWKV_FILE_VERSION_1
  RWKV_FILE_VERSION* = RWKV_FILE_VERSION_MAX

type
  RwkvErrorFlag* {.size: sizeof(uint32).} = enum
    rwkvErrorNone = 0,
    rwkvErrorAlloc = 1,
    rwkvErrorFileOpen = 2,
    rwkvErrorFileStat = 3,
    rwkvErrorFileRead = 4,
    rwkvErrorFileWrite = 5,
    rwkvErrorFileMagic = 6,
    rwkvErrorFileVersion = 7,
    rwkvErrorDataType = 8,
    rwkvErrorUnsupported = 9,
    rwkvErrorShape = 10,
    rwkvErrorDimension = 11,
    rwkvErrorKey = 12,
    rwkvErrorData = 13,
    rwkvErrorParamMissing = 14,
    rwkvErrorArgs = 1 shl 8,
    rwkvErrorFile = 2 shl 8,
    rwkvErrorModel = 3 shl 8,
    rwkvErrorModelParams = 4 shl 8,
    rwkvErrorGraph = 5 shl 8,
    rwkvErrorCtx = 6 shl 8

  RwkvContextObj* = object
  RwkvContext* = ptr RwkvContextObj

  RwkvModelObj* = object
    ctx*: RwkvContext
    isOwner*: bool

  RwkvModel* = ref RwkvModelObj

  RwkvException* = object of CatchableError
    errorCode*: uint32

# ---------------------------------------------------------------------------
# Runtime C API: proc-pointer globals (bound at runtime by bindBackend)
# ---------------------------------------------------------------------------
var
  rwkv_set_print_errors*: proc(ctx: RwkvContext, printErrors: bool) {.cdecl.}
  rwkv_get_print_errors*: proc(ctx: RwkvContext): bool {.cdecl.}
  rwkv_get_last_error*: proc(ctx: RwkvContext): uint32 {.cdecl.}
  rwkv_init_from_file*: proc(modelFilePath: cstring, nThreads: uint32, nGpuLayers: uint32): RwkvContext {.cdecl.}
  rwkv_clone_context*: proc(ctx: RwkvContext, nThreads: uint32): RwkvContext {.cdecl.}
  rwkv_eval*: proc(ctx: RwkvContext, token: uint32, stateIn: ptr float32, stateOut: ptr float32, logitsOut: ptr float32): bool {.cdecl.}
  rwkv_eval_sequence*: proc(ctx: RwkvContext, tokens: ptr uint32, sequenceLen: csize_t, stateIn: ptr float32, stateOut: ptr float32, logitsOut: ptr float32): bool {.cdecl.}
  rwkv_eval_sequence_in_chunks*: proc(ctx: RwkvContext, tokens: ptr uint32, sequenceLen: csize_t, chunkSize: csize_t, stateIn: ptr float32, stateOut: ptr float32, logitsOut: ptr float32): bool {.cdecl.}
  rwkv_get_n_vocab*: proc(ctx: RwkvContext): csize_t {.cdecl.}
  rwkv_get_n_embed*: proc(ctx: RwkvContext): csize_t {.cdecl.}
  rwkv_get_n_layer*: proc(ctx: RwkvContext): csize_t {.cdecl.}
  rwkv_get_state_len*: proc(ctx: RwkvContext): csize_t {.cdecl.}
  rwkv_get_logits_len*: proc(ctx: RwkvContext): csize_t {.cdecl.}
  rwkv_init_state*: proc(ctx: RwkvContext, state: ptr float32) {.cdecl.}
  rwkv_free*: proc(ctx: RwkvContext) {.cdecl.}
  rwkv_quantize_model_file*: proc(modelFilePathIn: cstring, modelFilePathOut: cstring, formatName: cstring): bool {.cdecl.}
  rwkv_get_system_info_string*: proc(): cstring {.cdecl.}

var loadedLib*: LibHandle = nil   # keep the bound library alive for the process

# ---------------------------------------------------------------------------
# Backend selection & binding (RFC 7500; single controlled switch point)
# ---------------------------------------------------------------------------
proc backendFor*(kind: RwkvBackendKind): RwkvBackend =
  ## Maps a backend kind to its runtime record. Backend modules (rwkv_cuda /
  ## rwkv_vulkan) are the LOWEST authority: they only know their lib.
  case kind
  of bkCuda:   cudaBackend()
  of bkVulkan: vulkanBackend()

proc selectBackend*(cfg: NimoConfig): RwkvBackend =
  ## Decides which backend to run: config file > compile-time default > backend modules.
  ## Returns the concrete RwkvBackend; hand it to bindBackend().
  # 1. explicit lib path (config) wins outright — overrides even the kind
  if cfg.libPath.len > 0:
    result = backendFor(cfg.backend)
    result.libPath = cfg.libPath
    return
  # 2. explicit backend choice from config file
  if cfg.backendSet:
    return backendFor(cfg.backend)
  # 3. rwkv-level compile-time default (flag -d:rwkvDefaultBackend=...)
  return backendFor(parseBackendKind(DefaultBackendKind))

proc bindBackend*(libPath: string) =
  ## Loads the given librwkv.so and binds every rwkv_* symbol into the globals
  ## above. THE single place that wires a backend lib into this process.
  ## Raises RwkvException (with the offending symbol) if the library is missing
  ## or is the wrong build, so problems surface as a clean message.
  let lib = loadLib(libPath)
  if lib == nil:
    raise newException(RwkvException, "cannot load backend librwkv.so: '" & libPath & "'")
  template require(name: string, sym: untyped) =
    sym = cast[type(sym)](symAddr(lib, name))
    if sym == nil:
      raise newException(RwkvException,
        "backend librwkv.so '" & libPath & "' is missing symbol '" & name &
        "' (wrong backend build?)")
  require("rwkv_set_print_errors", rwkv_set_print_errors)
  require("rwkv_get_print_errors", rwkv_get_print_errors)
  require("rwkv_get_last_error", rwkv_get_last_error)
  require("rwkv_init_from_file", rwkv_init_from_file)
  require("rwkv_clone_context", rwkv_clone_context)
  require("rwkv_eval", rwkv_eval)
  require("rwkv_eval_sequence", rwkv_eval_sequence)
  require("rwkv_eval_sequence_in_chunks", rwkv_eval_sequence_in_chunks)
  require("rwkv_get_n_vocab", rwkv_get_n_vocab)
  require("rwkv_get_n_embed", rwkv_get_n_embed)
  require("rwkv_get_n_layer", rwkv_get_n_layer)
  require("rwkv_get_state_len", rwkv_get_state_len)
  require("rwkv_get_logits_len", rwkv_get_logits_len)
  require("rwkv_init_state", rwkv_init_state)
  require("rwkv_free", rwkv_free)
  require("rwkv_quantize_model_file", rwkv_quantize_model_file)
  require("rwkv_get_system_info_string", rwkv_get_system_info_string)
  loadedLib = lib

proc ensureBackend*() =
  ## Binds the compile-time default backend if none is bound yet, so direct
  ## callers of initRwkvModel/quantizeModelFile without an explicit selection
  ## still work. Safe to call at any time.
  if loadedLib == nil:
    bindBackend(backendFor(parseBackendKind(DefaultBackendKind)).libPath)

# --- Pointer Conversion Helper Templates ---
template unsafePtr*[T](arr: openArray[T]): ptr T =
  if arr.len == 0: nil else: unsafeAddr(arr[0])

template varPtr*[T](arr: var openArray[T]): ptr T =
  if arr.len == 0: nil else: addr(arr[0])

# --- Model Property Getter Generator Template ---
template genModelGetter(name, cProc: untyped) =
  proc name*(model: RwkvModel): int {.inline.} =
    cProc(model.ctx).int

genModelGetter(nVocab, rwkv_get_n_vocab)
genModelGetter(nEmbed, rwkv_get_n_embed)
genModelGetter(nLayer, rwkv_get_n_layer)
genModelGetter(stateLen, rwkv_get_state_len)
genModelGetter(logitsLen, rwkv_get_logits_len)

proc `=destroy`*(model: var RwkvModelObj) =
  if model.ctx != nil and model.isOwner:
    rwkv_free(model.ctx)
    model.ctx = nil

proc close*(model: RwkvModel) =
  ## Explicitly frees underlying context before garbage collection.
  if model != nil and model.ctx != nil and model.isOwner:
    rwkv_free(model.ctx)
    model.ctx = nil

proc decodeError*(flags: uint32): string =
  ## Translates rwkv_error_flags bitmask into a descriptive string.
  if flags == 0: return "No error"

  let category = case flags and 0xFF00u32
    of 1u32 shl 8: "Args error"
    of 2u32 shl 8: "File error"
    of 3u32 shl 8: "Model error"
    of 4u32 shl 8: "Model params error"
    of 5u32 shl 8: "Graph error"
    of 6u32 shl 8: "Context error"
    else: ""

  let detail = case flags and 0x00FFu32
    of 1: "Allocation failed"
    of 2: "Failed to open file"
    of 3: "File stat failed"
    of 4: "File read failed"
    of 5: "File write failed"
    of 6: "Invalid file magic (expected GGML format model .bin file; PyTorch .pth files must be converted using convert_pytorch_to_ggml.py)"
    of 7: "Unsupported file version"
    of 8: "Unsupported data type"
    of 9: "Unsupported feature"
    of 10: "Invalid shape"
    of 11: "Invalid dimension"
    of 12: "Key error"
    of 13: "Data error"
    of 14: "Missing parameter"
    else: ""

  if category.len > 0 and detail.len > 0: category & ": " & detail
  elif category.len > 0: category
  else: detail

proc withSilentBackendInit[T](body: proc (): T): T =
  ## rwkv.cpp's ggml prints verbose CUDA init chatter (ggml_cuda_init:
  ## GGML_CUDA_FORCE_*…) to stdout/stderr on every model load. That noise is
  ## not useful to a human, so we silence both streams only for the duration of
  ## the backend init call and restore them right after. Real errors are not
  ## lost: a failed load sets the library's last-error string, which the caller
  ## reads via rwkv_get_last_error.
  when defined(linux):
    # dup stdout+stderr to a scratch fd, point them at /dev/null, run, restore.
    let oldOut = dup(1)
    let oldErr = dup(2)
    let devNull = open("/dev/null", O_WRONLY)
    if devNull >= 0 and oldOut >= 0 and oldErr >= 0:
      discard dup2(devNull, 1)
      discard dup2(devNull, 2)
      result = body()
      discard dup2(oldOut, 1)
      discard dup2(oldErr, 2)
      discard close(oldOut)
      discard close(oldErr)
      discard close(devNull)
    else:
      result = body()
      if oldOut >= 0: discard close(oldOut)
      if oldErr >= 0: discard close(oldErr)
      if devNull >= 0: discard close(devNull)
  else:
    result = body()

proc initRwkvModel*(modelPath: string, nThreads: uint32 = 4, nGpuLayers: uint32 = 99): RwkvModel =
  ## Loads model from GGML format file, offloading up to nGpuLayers to GPU VRAM.
  ## Binds the default backend automatically if none was selected explicitly.
  ensureBackend()
  let ctx = withSilentBackendInit(proc (): RwkvContext =
    rwkv_init_from_file(modelPath.cstring, nThreads, nGpuLayers))
  if ctx == nil:
    let err = rwkv_get_last_error(nil)
    raise newException(RwkvException, "Failed to load RWKV model from '" & modelPath & "': " & decodeError(err))
  RwkvModel(ctx: ctx, isOwner: true)

proc clone*(model: RwkvModel, nThreads: uint32 = 4): RwkvModel =
  ## Clones context for parallel inference execution.
  if model == nil or model.ctx == nil:
    raise newException(RwkvException, "Cannot clone uninitialized RwkvModel")
  let clonedCtx = rwkv_clone_context(model.ctx, nThreads)
  if clonedCtx == nil:
    let err = rwkv_get_last_error(model.ctx)
    raise newException(RwkvException, "Failed to clone RWKV context: " & decodeError(err))
  RwkvModel(ctx: clonedCtx, isOwner: true)

proc newState*(model: RwkvModel): seq[float32] =
  ## Allocates and initializes a new state buffer for inference.
  result = newSeq[float32](model.stateLen)
  if result.len > 0:
    rwkv_init_state(model.ctx, varPtr(result))

proc saveState*(state: openArray[float32], filePath: string) =
  ## Serializes raw model state float32 vector to a binary file.
  let f = open(filePath, fmWrite)
  defer: f.close()
  if state.len > 0:
    let written = f.writeBuffer(unsafeAddr state[0], state.len * sizeof(float32))
    if written != state.len * sizeof(float32):
      raise newException(IOError, "Failed to write complete state file to: " & filePath)

proc loadState*(state: var openArray[float32], filePath: string) =
  ## Deserializes binary state float32 vector into existing state array.
  let f = open(filePath, fmRead)
  defer: f.close()
  if state.len > 0:
    let bytesRead = f.readBuffer(addr state[0], state.len * sizeof(float32))
    if bytesRead != state.len * sizeof(float32):
      raise newException(IOError, "State file size mismatch: " & filePath)

proc loadState*(model: RwkvModel, filePath: string): seq[float32] =
  ## Allocates state buffer for model and deserializes binary state file.
  result = newSeq[float32](model.stateLen)
  result.loadState(filePath)

proc initState*(model: RwkvModel, state: var openArray[float32]) =
  ## Initializes an existing state array.
  if state.len != model.stateLen:
    raise newException(ValueError, &"State length mismatch: expected {model.stateLen}, got {state.len}")
  if state.len > 0:
    rwkv_init_state(model.ctx, varPtr(state))

proc newLogits*(model: RwkvModel): seq[float32] =
  newSeq[float32](model.logitsLen)

proc setPrintErrors*(model: RwkvModel = nil, printErrors: bool) =
  rwkv_set_print_errors(if model != nil: model.ctx else: nil, printErrors)

proc getPrintErrors*(model: RwkvModel = nil): bool =
  rwkv_get_print_errors(if model != nil: model.ctx else: nil)

proc getLastError*(model: RwkvModel = nil): uint32 =
  rwkv_get_last_error(if model != nil: model.ctx else: nil)

# --- DRY Metaprogrammed Model Evaluation Overloads ---

macro genEvalOverloads(nimProc, cProc: untyped, kind: static string): untyped =
  ## Macro: Metaprogrammatically generates raw-ptr, openArray slice, and in-place state overloads.
  case kind
  of "single":
    quote do:
      proc `nimProc`*(model: RwkvModel, token: uint32, stateIn: ptr float32 = nil; stateOut: ptr float32 = nil; logitsOut: ptr float32 = nil): bool {.inline.} =
        `cProc`(model.ctx, token, stateIn, stateOut, logitsOut)

      proc `nimProc`*(model: RwkvModel, token: uint32, stateIn: openArray[float32], stateOut, logitsOut: var openArray[float32]): bool {.inline.} =
        `cProc`(model.ctx, token, unsafePtr(stateIn), varPtr(stateOut), varPtr(logitsOut))

      proc `nimProc`*(model: RwkvModel, token: uint32, stateInOut, logitsOut: var openArray[float32]): bool {.inline.} =
        `cProc`(model.ctx, token, varPtr(stateInOut), varPtr(stateInOut), varPtr(logitsOut))

  of "sequence":
    quote do:
      proc `nimProc`*(model: RwkvModel, tokens: openArray[uint32], stateIn: ptr float32 = nil; stateOut: ptr float32 = nil; logitsOut: ptr float32 = nil): bool {.inline.} =
        `cProc`(model.ctx, unsafePtr(tokens), tokens.len.csize_t, stateIn, stateOut, logitsOut)

      proc `nimProc`*(model: RwkvModel, tokens: openArray[uint32], stateIn: openArray[float32], stateOut, logitsOut: var openArray[float32]): bool {.inline.} =
        `cProc`(model.ctx, unsafePtr(tokens), tokens.len.csize_t, unsafePtr(stateIn), varPtr(stateOut), varPtr(logitsOut))

      proc `nimProc`*(model: RwkvModel, tokens: openArray[uint32], stateInOut, logitsOut: var openArray[float32]): bool {.inline.} =
        `cProc`(model.ctx, unsafePtr(tokens), tokens.len.csize_t, varPtr(stateInOut), varPtr(stateInOut), varPtr(logitsOut))

  of "chunked":
    quote do:
      proc `nimProc`*(model: RwkvModel, tokens: openArray[uint32], chunkSize: int = 16; stateIn: ptr float32 = nil; stateOut: ptr float32 = nil; logitsOut: ptr float32 = nil): bool {.inline.} =
        `cProc`(model.ctx, unsafePtr(tokens), tokens.len.csize_t, chunkSize.csize_t, stateIn, stateOut, logitsOut)

      proc `nimProc`*(model: RwkvModel, tokens: openArray[uint32], chunkSize: int, stateIn: openArray[float32], stateOut, logitsOut: var openArray[float32]): bool {.inline.} =
        `cProc`(model.ctx, unsafePtr(tokens), tokens.len.csize_t, chunkSize.csize_t, unsafePtr(stateIn), varPtr(stateOut), varPtr(logitsOut))

      proc `nimProc`*(model: RwkvModel, tokens: openArray[uint32], chunkSize: int, stateInOut, logitsOut: var openArray[float32]): bool {.inline.} =
        `cProc`(model.ctx, unsafePtr(tokens), tokens.len.csize_t, chunkSize.csize_t, varPtr(stateInOut), varPtr(stateInOut), varPtr(logitsOut))
  else:
    error("Unknown eval overload kind: " & kind)

genEvalOverloads(eval, rwkv_eval, "single")
genEvalOverloads(evalSequence, rwkv_eval_sequence, "sequence")
genEvalOverloads(evalSequenceInChunks, rwkv_eval_sequence_in_chunks, "chunked")

proc quantizeModelFile*(modelFilePathIn, modelFilePathOut: string, formatName: string): bool =
  ensureBackend()
  rwkv_quantize_model_file(modelFilePathIn.cstring, modelFilePathOut.cstring, formatName.cstring)

proc getSystemInfo*(): string =
  let p = rwkv_get_system_info_string()
  if p != nil: $p else: ""
