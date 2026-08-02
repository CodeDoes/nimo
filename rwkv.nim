## Nim wrapper for rwkv.cpp
## High-performance C/C++ implementation of RWKV language model inference.

const libRwkv* {.strdefine.} = (when defined(windows): "rwkv.dll" elif defined(macosx): "librwkv.dylib" else: "librwkv.so")

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

proc `=destroy`*(model: var RwkvModelObj) =
  if model.ctx != nil and model.isOwner:
    rwkv_free(model.ctx)
    model.ctx = nil

proc close*(model: RwkvModel) =
  ## Explicitly frees the underlying context before garbage collection.
  if model != nil and model.ctx != nil and model.isOwner:
    rwkv_free(model.ctx)
    model.ctx = nil

proc decodeError*(flags: uint32): string =
  ## Translates rwkv_error_flags bitmask into a descriptive string.
  if flags == 0:
    return "No error"
  var category = ""
  var detail = ""
  let catBits = flags and 0xFF00u32
  let detailBits = flags and 0x00FFu32
  case catBits
  of 1u32 shl 8: category = "Args error"
  of 2u32 shl 8: category = "File error"
  of 3u32 shl 8: category = "Model error"
  of 4u32 shl 8: category = "Model params error"
  of 5u32 shl 8: category = "Graph error"
  of 6u32 shl 8: category = "Context error"
  else: category = if catBits != 0: "Unknown category (" & $catBits & ")" else: ""

  case detailBits
  of 1: detail = "Allocation failed"
  of 2: detail = "Failed to open file"
  of 3: detail = "File stat failed"
  of 4: detail = "File read failed"
  of 5: detail = "File write failed"
  of 6: detail = "Invalid file magic"
  of 7: detail = "Unsupported file version"
  of 8: detail = "Unsupported data type"
  of 9: detail = "Unsupported feature"
  of 10: detail = "Invalid shape"
  of 11: detail = "Invalid dimension"
  of 12: detail = "Key error"
  of 13: detail = "Data error"
  of 14: detail = "Missing parameter"
  else: detail = if detailBits != 0: "Unknown detail code (" & $detailBits & ")" else: ""

  if category.len > 0 and detail.len > 0:
    return category & ": " & detail
  elif category.len > 0:
    return category
  else:
    return detail

proc initRwkvModel*(modelPath: string, nThreads: uint32 = 4, nGpuLayers: uint32 = 0): RwkvModel =
  ## Loads the model from a GGML format file.
  ## Raises RwkvException on failure.
  let ctx = rwkv_init_from_file(modelPath.cstring, nThreads, nGpuLayers)
  if ctx == nil:
    let err = rwkv_get_last_error(nil)
    raise newException(RwkvException, "Failed to load RWKV model from '" & modelPath & "': " & decodeError(err))
  result = RwkvModel(ctx: ctx, isOwner: true)

proc clone*(model: RwkvModel, nThreads: uint32 = 4): RwkvModel =
  ## Clones a context for parallel inference (each clone can run an eval in parallel).
  if model == nil or model.ctx == nil:
    raise newException(RwkvException, "Cannot clone uninitialized RwkvModel")
  let clonedCtx = rwkv_clone_context(model.ctx, nThreads)
  if clonedCtx == nil:
    let err = rwkv_get_last_error(model.ctx)
    raise newException(RwkvException, "Failed to clone RWKV context: " & decodeError(err))
  result = RwkvModel(ctx: clonedCtx, isOwner: true)

proc nVocab*(model: RwkvModel): int {.inline.} =
  rwkv_get_n_vocab(model.ctx).int

proc nEmbed*(model: RwkvModel): int {.inline.} =
  rwkv_get_n_embed(model.ctx).int

proc nLayer*(model: RwkvModel): int {.inline.} =
  rwkv_get_n_layer(model.ctx).int

proc stateLen*(model: RwkvModel): int {.inline.} =
  rwkv_get_state_len(model.ctx).int

proc logitsLen*(model: RwkvModel): int {.inline.} =
  rwkv_get_logits_len(model.ctx).int

proc newState*(model: RwkvModel): seq[float32] =
  ## Allocates and initializes a new state buffer for inference.
  let size = model.stateLen
  result = newSeq[float32](size)
  if size > 0:
    rwkv_init_state(model.ctx, addr result[0])

proc initState*(model: RwkvModel, state: var openArray[float32]) =
  ## Initializes an existing state array.
  if state.len != model.stateLen:
    raise newException(ValueError, "State length mismatch: expected " & $model.stateLen & ", got " & $state.len)
  if state.len > 0:
    rwkv_init_state(model.ctx, addr state[0])

proc newLogits*(model: RwkvModel): seq[float32] =
  ## Allocates a new logits buffer.
  newSeq[float32](model.logitsLen)

proc setPrintErrors*(model: RwkvModel = nil, printErrors: bool) =
  let ctx = if model != nil: model.ctx else: nil
  rwkv_set_print_errors(ctx, printErrors)

proc getPrintErrors*(model: RwkvModel = nil): bool =
  let ctx = if model != nil: model.ctx else: nil
  rwkv_get_print_errors(ctx)

proc getLastError*(model: RwkvModel = nil): uint32 =
  let ctx = if model != nil: model.ctx else: nil
  rwkv_get_last_error(ctx)

proc eval*(
  model: RwkvModel,
  token: uint32,
  stateIn: ptr float32 = nil,
  stateOut: ptr float32 = nil,
  logitsOut: ptr float32 = nil
): bool {.inline.} =
  ## Evaluates model for a single token using raw pointers.
  rwkv_eval(model.ctx, token, stateIn, stateOut, logitsOut)

proc eval*(
  model: RwkvModel,
  token: uint32,
  stateIn: openArray[float32],
  stateOut: var openArray[float32],
  logitsOut: var openArray[float32]
): bool =
  ## Evaluates model for a single token using Nim slices/openArrays.
  let pIn = if stateIn.len == 0: nil else: unsafeAddr(stateIn[0])
  let pOut = if stateOut.len == 0: nil else: addr(stateOut[0])
  let pLogits = if logitsOut.len == 0: nil else: addr(logitsOut[0])
  rwkv_eval(model.ctx, token, pIn, pOut, pLogits)

proc eval*(
  model: RwkvModel,
  token: uint32,
  stateInOut: var openArray[float32],
  logitsOut: var openArray[float32]
): bool =
  ## Evaluates model for a single token updating stateInOut in-place.
  let pState = if stateInOut.len == 0: nil else: addr(stateInOut[0])
  let pLogits = if logitsOut.len == 0: nil else: addr(logitsOut[0])
  rwkv_eval(model.ctx, token, pState, pState, pLogits)

proc evalSequence*(
  model: RwkvModel,
  tokens: openArray[uint32],
  stateIn: ptr float32 = nil,
  stateOut: ptr float32 = nil,
  logitsOut: ptr float32 = nil
): bool {.inline.} =
  ## Evaluates model for a sequence of tokens using raw pointers.
  let pTokens = if tokens.len == 0: nil else: unsafeAddr(tokens[0])
  rwkv_eval_sequence(model.ctx, pTokens, tokens.len.csize_t, stateIn, stateOut, logitsOut)

proc evalSequence*(
  model: RwkvModel,
  tokens: openArray[uint32],
  stateIn: openArray[float32],
  stateOut: var openArray[float32],
  logitsOut: var openArray[float32]
): bool =
  ## Evaluates model for a sequence of tokens using Nim openArrays.
  let pTokens = if tokens.len == 0: nil else: unsafeAddr(tokens[0])
  let pIn = if stateIn.len == 0: nil else: unsafeAddr(stateIn[0])
  let pOut = if stateOut.len == 0: nil else: addr(stateOut[0])
  let pLogits = if logitsOut.len == 0: nil else: addr(logitsOut[0])
  rwkv_eval_sequence(model.ctx, pTokens, tokens.len.csize_t, pIn, pOut, pLogits)

proc evalSequence*(
  model: RwkvModel,
  tokens: openArray[uint32],
  stateInOut: var openArray[float32],
  logitsOut: var openArray[float32]
): bool =
  ## Evaluates model for a sequence of tokens updating stateInOut in-place.
  let pTokens = if tokens.len == 0: nil else: unsafeAddr(tokens[0])
  let pState = if stateInOut.len == 0: nil else: addr(stateInOut[0])
  let pLogits = if logitsOut.len == 0: nil else: addr(logitsOut[0])
  rwkv_eval_sequence(model.ctx, pTokens, tokens.len.csize_t, pState, pState, pLogits)

proc evalSequenceInChunks*(
  model: RwkvModel,
  tokens: openArray[uint32],
  chunkSize: int = 16,
  stateIn: ptr float32 = nil,
  stateOut: ptr float32 = nil,
  logitsOut: ptr float32 = nil
): bool {.inline.} =
  ## Evaluates sequence splitting into chunks using raw pointers.
  let pTokens = if tokens.len == 0: nil else: unsafeAddr(tokens[0])
  rwkv_eval_sequence_in_chunks(model.ctx, pTokens, tokens.len.csize_t, chunkSize.csize_t, stateIn, stateOut, logitsOut)

proc evalSequenceInChunks*(
  model: RwkvModel,
  tokens: openArray[uint32],
  chunkSize: int,
  stateIn: openArray[float32],
  stateOut: var openArray[float32],
  logitsOut: var openArray[float32]
): bool =
  ## Evaluates sequence splitting into chunks using Nim openArrays.
  let pTokens = if tokens.len == 0: nil else: unsafeAddr(tokens[0])
  let pIn = if stateIn.len == 0: nil else: unsafeAddr(stateIn[0])
  let pOut = if stateOut.len == 0: nil else: addr(stateOut[0])
  let pLogits = if logitsOut.len == 0: nil else: addr(logitsOut[0])
  rwkv_eval_sequence_in_chunks(model.ctx, pTokens, tokens.len.csize_t, chunkSize.csize_t, pIn, pOut, pLogits)

proc evalSequenceInChunks*(
  model: RwkvModel,
  tokens: openArray[uint32],
  chunkSize: int,
  stateInOut: var openArray[float32],
  logitsOut: var openArray[float32]
): bool =
  ## Evaluates sequence splitting into chunks updating stateInOut in-place.
  let pTokens = if tokens.len == 0: nil else: unsafeAddr(tokens[0])
  let pState = if stateInOut.len == 0: nil else: addr(stateInOut[0])
  let pLogits = if logitsOut.len == 0: nil else: addr(logitsOut[0])
  rwkv_eval_sequence_in_chunks(model.ctx, pTokens, tokens.len.csize_t, chunkSize.csize_t, pState, pState, pLogits)

proc quantizeModelFile*(modelFilePathIn, modelFilePathOut: string, formatName: string): bool =
  ## Quantizes FP32 or FP16 model file to quantized format (Q4_0, Q4_1, Q5_0, Q5_1, Q8_0).
  rwkv_quantize_model_file(modelFilePathIn.cstring, modelFilePathOut.cstring, formatName.cstring)

proc getSystemInfo*(): string =
  ## Returns system information string.
  let p = rwkv_get_system_info_string()
  if p != nil: $p else: ""
