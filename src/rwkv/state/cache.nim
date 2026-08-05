## rwkv/state/cache.nim — State cache manager.
##
## RFC 8000 state baking: pre-compute the model state for a fixed context
## (e.g. system prompt) once and cache it, keyed by
## (model file signature | vocab file hash | context hash), so sessions can
## resume instantly instead of re-evaluating the prompt every time.
##
## Cache math (keys, paths, save/load) is offline-safe; only the actual bake
## (tokenize + eval) needs the real model backend.

import std/[os, sha1]
import ../../config, ../../model_cache
when not defined(harnessOffline):
  import ../../rwkv, ../../tokenizer, ../../macros

type
  StateCache* = object
    cacheDir*: string

const StateFileExt = ".state.bin"

proc initStateCache*(cacheDir: string = DefaultStateCacheDir): StateCache =
  result.cacheDir = cacheDir

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
  let dir = parentDir(path)
  if dir.len > 0 and dir != ".":
    createDir(dir)
  let f = open(path, fmWrite)
  defer: f.close()
  if state.len > 0:
    if f.writeBuffer(unsafeAddr state[0], state.len * sizeof(float32)) !=
       state.len * sizeof(float32):
      raise newException(IOError, "Failed to write state file: " & path)

proc loadStateFromFile*(state: var openArray[float32], path: string): bool =
  ## Loads a state vector; returns false on size mismatch / IO error.
  if not fileExists(path):
    return false
  if getFileSize(path) != state.len * sizeof(float32):
    return false
  let f = open(path, fmRead)
  defer: f.close()
  if f.readBuffer(addr state[0], state.len * sizeof(float32)) !=
     state.len * sizeof(float32):
    return false
  return true

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

when not defined(harnessOffline):
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
