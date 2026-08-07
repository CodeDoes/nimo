## rwkv/state/cache.nim — State cache manager.
##
## RFC 8000 state baking: pre-compute the model state for a fixed context
## (e.g. system prompt) once and cache it, keyed by
## (model file signature | vocab file hash | context hash), so sessions can
## resume instantly instead of re-evaluating the prompt every time.
##
## Cache math (keys, paths, save/load) needs no backend; only the actual bake
## (tokenize + eval) touches the model, and that only happens when a real
## model is present (runtime decision — no compile-time fork).

import std/[os, strutils, sha1, algorithm]
import ../../config, ../../model_cache
import ../../rwkv, ../../tokenizer, ../../macros

type
  StateCache* = object
    cacheDir*: string

const
  StateFileExt = ".state.bin"
  StateCacheMaxBytes = 512 * 1024 * 1024   # 512 MB cap — states are 21 MB each

proc pruneStateCache*(c: StateCache, maxBytes: int64 = StateCacheMaxBytes): int =
  ## Deletes oldest cached state files until the cache fits under `maxBytes`.
  ## Returns the number of files removed. Keeps the newest states (most likely
  ## to match the current model/config).
  if not dirExists(c.cacheDir):
    return 0
  var files: seq[(int64, string)]
  for kind, p in walkDir(c.cacheDir):
    if kind == pcFile and p.endsWith(StateFileExt):
      try: files.add((getFileSize(p), p))
      except CatchableError: discard
  if files.len <= 1:
    return 0
  var total: int64 = 0
  for (sz, _) in files: total += sz
  files.sort(proc (a, b: (int64, string)): int =
    # sort oldest-first so we remove from the oldest end
    if a[1] < b[1]: result = -1
    elif a[1] > b[1]: result = 1
    else: result = 0)
  var removed = 0
  for (sz, p) in files:
    if total <= maxBytes: break
    try:
      removeFile(p)
      total -= sz
      inc removed
    except CatchableError: discard
  removed

proc initStateCache*(cacheDir: string = DefaultStateCacheDir): StateCache =
  result.cacheDir = cacheDir
  # Keep cached states from taking over the disk across many runs/model
  # variants: drop the oldest until under the cap. Harmless — a pruned state
  # is simply re-baked on next use.
  discard pruneStateCache(result)

proc stateCacheKey*(modelPath, vocabPath, context: string): string =
  ## Cache key per RFC 8000: model file hash + vocab hash + prompt content.
  let modelId = modelSignature(modelPath)
  var vocabId = ""
  if fileExists(vocabPath):
    vocabId = $secureHash(readFile(vocabPath))   # vocab files are small
  result = $secureHash(modelId & "|" & vocabId & "|" & context)

proc statePath*(c: StateCache, key: string): string =
  ## <cacheDir>/<key12>.state.bin
  c.cacheDir / (key[0 ..< min(12, key.len)] & StateFileExt)

proc saveStateToFile*(state: openArray[float32], path: string) =
  ## Writes a float32 state vector to disk (little-endian, raw).
  try:
    let dir = parentDir(path)
    if dir.len > 0 and dir != ".":
      createDir(dir)
    var f: File
    if not f.open(path, fmWrite):
      raise newException(IOError, "Failed to open state file for writing: " & path)
    defer: f.close()
    if state.len > 0:
      if f.writeBuffer(unsafeAddr state[0], state.len * sizeof(float32)) !=
         state.len * sizeof(float32):
        raise newException(IOError, "Failed to write state file buffer: " & path)
  except CatchableError as e:
    raise newException(IOError, "saveStateToFile failed for path " & path & ": " & e.msg)

proc loadStateFromFile*(state: var openArray[float32], path: string): bool =
  ## Loads a state vector; returns false on size mismatch / IO error.
  if not fileExists(path):
    return false
  try:
    if getFileSize(path) != state.len * sizeof(float32):
      return false
    var f: File
    if not f.open(path, fmRead):
      return false
    defer: f.close()
    if f.readBuffer(addr state[0], state.len * sizeof(float32)) !=
       state.len * sizeof(float32):
      return false
    # Sanity: a garbled/corrupted state (same size, junk bytes) shows up as
    # NaN/Inf floats. Reject it so the caller treats the cache as a miss and
    # re-bakes instead of silently generating garbage (RFC 8000 self-heal).
    for v in state:
      if v != v or v == Inf or v == -Inf:
        return false
    return true
  except CatchableError:
    return false

proc loadCachedState*(c: StateCache, modelPath, vocabPath, context: string,
                      stateLen: int): seq[float32] =
  ## Returns the cached baked state or an EMPTY seq on miss / mismatch.
  ## (Nim 2.x seqs cannot hold nil.)
  let p = c.statePath(stateCacheKey(modelPath, vocabPath, context))
  if not fileExists(p):
    return @[]
  if getFileSize(p) != stateLen * sizeof(float32):
    return @[]
  result = newSeq[float32](stateLen)
  if not loadStateFromFile(result, p):
    return @[]

proc bakeContext*(c: StateCache, model: RwkvModel, tok: WorldTokenizer,
                    modelPath, vocabPath, context: string): seq[float32] =
    ## Tokenizes `context`, runs it through the model to produce the state,
    ## caches it keyed by (model, vocab, context), and returns it.
    let key = stateCacheKey(modelPath, vocabPath, context)
    let cached = c.loadCachedState(modelPath, vocabPath, context, model.stateLen)
    if cached.len > 0:
      return cached

    let tokens = tok.encode(context)
    result = model.newState()
    var logits = model.newLogits()
    if tokens.len > 0:
      checkOk(model.evalSequenceInChunks(tokens, DefaultChunkSize, result, logits),
              "Failed to evaluate context for state baking")
    saveStateToFile(result, c.statePath(key))

proc resumeFromCache*(c: StateCache, model: RwkvModel, tok: WorldTokenizer,
                      modelPath, vocabPath, context: string): seq[float32] =
  ## Like `bakeContext` but never evaluates: returns nil unless the state is
  ## already cached (strict resume, no bake-on-miss).
  c.loadCachedState(modelPath, vocabPath, context, model.stateLen)
