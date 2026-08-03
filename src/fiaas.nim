## FIAAS - Fictional Artificial Intelligence Associative Storage
## Simulated vector embedding search for memory retrieval.

import std/[math, strutils, hashes, random, times, tables, os]
import ./config

type
  MemoryEntry* = ref object
    id*: string
    timestamp*: string
    text*: string
    embedding*: seq[float64]
    metadata*: Table[string, string]
    category*: string  # character, scene, plot, theme

  FIAAS* = ref object
    entries*: seq[MemoryEntry]
    dimension*: int
    rng*: Rand

const
  DefaultDimension* = 64
  DefaultCategory* = "general"

proc newFIAAS*(dimension: int = DefaultDimension): FIAAS =
  result = FIAAS.new()
  result.dimension = dimension
  result.rng = initRand(cpuTime().int64)

proc hashToEmbedding*(text: string, dimension: int): seq[float64] =
  result = newSeq[float64](dimension)
  var h = 12345
  for i in 0 ..< dimension:
    h = h * 1103515245 + 12345
    result[i] = float64(((h shr 16) and 0x7FFF) - 0x4000) / 16384.0

proc cosineSimilarity*(a, b: seq[float64]): float64 =
  var dotProduct = 0.0
  var normA = 0.0
  var normB = 0.0
  for i in 0 ..< a.len:
    dotProduct += a[i] * b[i]
    normA += a[i] * a[i]
    normB += b[i] * b[i]
  if normA == 0 or normB == 0: return 0.0
  return dotProduct / (sqrt(normA) * sqrt(normB))

proc addEntry*(s: var FIAAS, text: string, category: string = DefaultCategory,
               metadata: Table[string, string] = initTable[string,string]()): string =
  let id = "mem_" & $s.entries.len
  let entry = MemoryEntry(
    id: id,
    timestamp: "",
    text: text,
    embedding: hashToEmbedding(text, s.dimension),
    metadata: metadata,
    category: category
  )
  s.entries.add(entry)
  return id

proc search*(s: FIAAS, query: string, topK: int = 5): seq[tuple[id: string, score: float64, text: string]] =
  let queryEmbedding = hashToEmbedding(query, s.dimension)
  var scores: seq[tuple[id: string, score: float64, text: string]] = @[]
  
  for entry in s.entries:
    let sim = cosineSimilarity(queryEmbedding, entry.embedding)
    scores.add((id: entry.id, score: sim, text: entry.text))
  
  # Bubble sort by score descending
  for i in 0 ..< scores.len:
    for j in i+1 ..< scores.len:
      if scores[j].score > scores[i].score:
        let temp = scores[i]
        scores[i] = scores[j]
        scores[j] = temp
  
  if scores.len > topK:
    return scores[0 ..< topK]
  return scores

proc searchByCategory*(s: FIAAS, category: string, topK: int = 5): seq[tuple[id: string, score: float64, text: string]] =
  var results: seq[tuple[id: string, score: float64, text: string]] = @[]
  for entry in s.entries:
    if entry.category == category:
      results.add((id: entry.id, score: 1.0, text: entry.text))
  if results.len > topK:
    return results[0 ..< topK]
  return results

proc getEntry*(s: FIAAS, id: string): MemoryEntry =
  for entry in s.entries:
    if entry.id == id:
      return entry
  raise newException(KeyError, "Memory entry not found: " & id)

proc count*(s: FIAAS): int =
  return s.entries.len

proc listEntries*(s: FIAAS): seq[string] =
  result = @[]
  for entry in s.entries:
    result.add("{entry.id} [{entry.category}] - " & entry.text[0 ..< min(50, entry.text.len)] & "...")

proc clear*(s: var FIAAS) =
  s.entries = @[]

proc saveToFile*(s: FIAAS, path: string) =
  let dir = parentDir(path)
  if dir.len > 0 and dir != ".":
    createDir(dir)
  var j = newJObject()
  j["dimension"] = %s.dimension
  var entries = newJArray()
  for entry in s.entries:
    var ej = newJObject()
    ej["id"] = %entry.id
    ej["timestamp"] = %entry.timestamp
    ej["text"] = %entry.text
    ej["category"] = %entry.category
    var meta = newJObject()
    for k, v in entry.metadata.pairs:
      meta[k] = %v
    ej["metadata"] = meta
    entries.add(ej)
  j["entries"] = entries
  writeFile(path, $j)

proc loadFromFile*(s: var FIAAS, path: string): bool =
  if not fileExists(path):
    return false
  try:
    let j = parseJson(readFile(path))
    s.dimension = j["dimension"].getInt(DefaultDimension)
    s.entries = @[]
    for ej in j["entries"]:
      let entry = MemoryEntry(
        id: ej["id"].str,
        timestamp: ej["timestamp"].str,
        text: ej["text"].str,
        embedding: hashToEmbedding(ej["text"].str, s.dimension),
        metadata: initTable[string, string](),
        category: ej["category"].str
      )
      if "metadata" in ej:
        for k, v in ej["metadata"].pairs:
          entry.metadata[k] = v.str
      s.entries.add(entry)
    return true
  except:
    return false
