## Context + State Cache Integration
## Combines context caching with state baking for optimal performance.

import std/[strutils, os, times, json]
import ./config, ./state_cache, ./model_cache, ./session_manager, ./tokenizer, ./rwkv

type
  ContextStateCache* = ref object
    stateCache*: StateCache
    modelCache*: ModelCache
    lastBakeTime*: float
    bakeCount*: int
    hitCount*: int
    missCount*: int

proc newContextStateCache*(stateCacheDir: string = DefaultStateCacheDir,
                           modelCacheDir: string = DefaultModelCacheDir): ContextStateCache =
  result = ContextStateCache.new()
  result.stateCache = initStateCache(stateCacheDir)
  result.modelCache = initModelCache(modelCacheDir)
  result.lastBakeTime = 0.0
  result.bakeCount = 0
  result.hitCount = 0
  result.missCount = 0

proc getOrBake*(c: var ContextStateCache, model: RwkvModel, tok: WorldTokenizer,
                modelPath, vocabPath, context: string): seq[float32] =
  let cached = c.stateCache.loadCachedState(modelPath, vocabPath, context, model.stateLen)
  if cached.len > 0:
    inc c.hitCount
    return cached
  
  inc c.missCount
  inc c.bakeCount
  c.lastBakeTime = cpuTime()
  return c.stateCache.bakeContext(model, tok, modelPath, vocabPath, context)

proc getStats*(c: ContextStateCache): string =
  let total = c.hitCount + c.missCount
  let hitRate = if total > 0: float(c.hitCount) / float(total) * 100.0 else: 0.0
  return "Bakes: " & $c.bakeCount & ", Hits: " & $c.hitCount & ", Misses: " & $c.missCount & ", Hit Rate: " & $hitRate & "%"

proc saveStats*(c: ContextStateCache, path: string) =
  let dir = parentDir(path)
  if dir.len > 0 and dir != ".":
    createDir(dir)
  
  let configContent = "{\"bakeCount\": " & $c.bakeCount & ", \"hitCount\": " & $c.hitCount & ", \"missCount\": " & $c.missCount & ", \"lastBakeTime\": " & $c.lastBakeTime & "}"
  writeFile(path, configContent)

proc loadStats*(c: var ContextStateCache, path: string): bool =
  if not fileExists(path):
    return false
  
  try:
    let j = parseJson(readFile(path))
    c.bakeCount = j["bakeCount"].getInt(0)
    c.hitCount = j["hitCount"].getInt(0)
    c.missCount = j["missCount"].getInt(0)
    c.lastBakeTime = j["lastBakeTime"].getFloat(0.0)
    return true
  except:
    return false

proc ensureModelCached*(c: var ContextStateCache, rawPath: string, format: string): tuple[path: string, cached: bool] =
  return c.modelCache.ensureQuantized(rawPath, format)
