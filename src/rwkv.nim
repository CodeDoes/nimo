## Nim wrapper for rwkv.cpp
## High-performance C/C++ implementation of RWKV language model inference.

import std/[macros, strformat]

when defined(linux):
  {.passL: "-lstdc++ -fopenmp -Wl,-rpath,/usr/lib/x86_64-linux-gnu -Wl,-rpath,/run/opengl-driver/lib -Wl,-rpath,$ORIGIN/rwkv.cpp -Wl,-rpath,$ORIGIN/rwkv.cpp/ggml/src -Wl,-rpath,rwkv.cpp -Wl,-rpath,rwkv.cpp/ggml/src".}

const libRwkv* {.strdefine.} = (
  when defined(windows):
    "(rwkv.dll|./rwkv.dll|rwkv.cpp/rwkv.dll)"
  elif defined(macosx):
    "(librwkv.dylib|./librwkv.dylib|rwkv.cpp/librwkv.dylib)"
  else:
    "(librwkv.so|./librwkv.so|rwkv.cpp/librwkv.so)"
)

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

{.push cdecl, dynlib: libRwkv.}
proc rwkv_set_print_errors*(ctx: RwkvContext, printErrors: bool) {.importc: "rwkv_set_print_errors".}
proc rwkv_get_print_errors*(ctx: RwkvContext): bool {.importc: "rwkv_get_print_errors".}
proc rwkv_get_last_error*(ctx: RwkvContext): uint32 {.importc: "rwkv_get_last_error".}
proc rwkv_init_from_file*(modelFilePath: cstring, nThreads: uint32, nGpuLayers: uint32): RwkvContext {.importc: "rwkv_init_from_file".}
proc rwkv_clone_context*(ctx: RwkvContext, nThreads: uint32): RwkvContext {.importc: "rwkv_clone_context".}
proc rwkv_eval*(ctx: RwkvContext, token: uint32, stateIn: ptr float32, stateOut: ptr float32, logitsOut: ptr float32): bool {.importc: "rwkv_eval".}
proc rwkv_eval_sequence*(ctx: RwkvContext, tokens: ptr uint32, sequenceLen: csize_t, stateIn: ptr float32, stateOut: ptr float32, logitsOut: ptr float32): bool {.importc: "rwkv_eval_sequence".}
proc rwkv_eval_sequence_in_chunks*(ctx: RwkvContext, tokens: ptr uint32, sequenceLen: csize_t, chunkSize: csize_t, stateIn: ptr float32, stateOut: ptr float32, logitsOut: ptr float32): bool {.importc: "rwkv_eval_sequence_in_chunks".}
proc rwkv_get_n_vocab*(ctx: RwkvContext): csize_t {.importc: "rwkv_get_n_vocab".}
proc rwkv_get_n_embed*(ctx: RwkvContext): csize_t {.importc: "rwkv_get_n_embed".}
proc rwkv_get_n_layer*(ctx: RwkvContext): csize_t {.importc: "rwkv_get_n_layer".}
proc rwkv_get_state_len*(ctx: RwkvContext): csize_t {.importc: "rwkv_get_state_len".}
proc rwkv_get_logits_len*(ctx: RwkvContext): csize_t {.importc: "rwkv_get_logits_len".}
proc rwkv_init_state*(ctx: RwkvContext, state: ptr float32) {.importc: "rwkv_init_state".}
proc rwkv_free*(ctx: RwkvContext) {.importc: "rwkv_free".}
proc rwkv_quantize_model_file*(modelFilePathIn: cstring, modelFilePathOut: cstring, formatName: cstring): bool {.importc: "rwkv_quantize_model_file".}
proc rwkv_get_system_info_string*(): cstring {.importc: "rwkv_get_system_info_string".}
{.pop.}

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

proc initRwkvModel*(modelPath: string, nThreads: uint32 = 4, nGpuLayers: uint32 = 99): RwkvModel =
  ## Loads model from GGML format file, offloading up to nGpuLayers to GPU VRAM.
  let ctx = rwkv_init_from_file(modelPath.cstring, nThreads, nGpuLayers)
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
  rwkv_quantize_model_file(modelFilePathIn.cstring, modelFilePathOut.cstring, formatName.cstring)

proc getSystemInfo*(): string =
  let p = rwkv_get_system_info_string()
  if p != nil: $p else: ""
