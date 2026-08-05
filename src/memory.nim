## Memory System for NIMO
## Integrates FIAAS with session management for persistent context.

import std/[json, strutils, os, times, tables, strformat]
import ./fiaas, ./session_manager, ./workspace, ./config

type
  MemoryStore* = ref object
    fiaas*: FIAAS
    sessions*: seq[string]
    characters*: Table[string,string]  # character name -> memory ID

proc newMemoryStore*(): MemoryStore =
  result = MemoryStore.new()
  result.fiaas = newFIAAS()

proc addMemory*(s: var MemoryStore, text: string, category: string = "general",
                metadata: Table[string,string] = initTable[string,string]()): string =
  ## Adds a memory entry and returns its ID.
  return s.fiaas.addEntry(text, category, metadata)

proc searchMemory*(s: MemoryStore, query: string, topK: int = 5): seq[string] =
  ## Searches for relevant memories.
  let results = s.fiaas.search(query, topK)
  var memories: seq[string] = @[]
  for r in results:
    memories.add(r.text)
  return memories

proc searchByCategory*(s: MemoryStore, category: string, topK: int = 5): seq[string] =
  ## Searches for memories in a category.
  let results = s.fiaas.searchByCategory(category, topK)
  var memories: seq[string] = @[]
  for r in results:
    memories.add(r.text)
  return memories

proc rememberCharacter*(s: var MemoryStore, name: string, description: string) =
  ## Stores character information.
  let id = s.addMemory(description, "character", {"name": name}.toTable)
  s.characters[name] = id

proc getCharacterMemory*(s: MemoryStore, name: string): string =
  ## Retrieves character memory.
  if name in s.characters:
    try:
      let entry = s.fiaas.getEntry(s.characters[name])
      return entry.text
    except:
      return ""
  return ""

proc saveMemory*(s: MemoryStore, path: string) =
  ## Saves memory to file.
  s.fiaas.saveToFile(path)

proc loadMemory*(s: var MemoryStore, path: string): bool =
  ## Loads memory from file.
  return s.fiaas.loadFromFile(path)

proc getRelevantContext*(s: MemoryStore, currentText: string, maxTokens: int = 500): string =
  ## Gets relevant context for the current text.
  let memories = s.searchMemory(currentText, 3)
  var context = ""
  var tokenCount = 0
  for mem in memories:
    if tokenCount + mem.len > maxTokens:
      break
    context.add(mem & "\n")
    tokenCount += mem.len
  return context.strip()

# ---------------------------------------------------------------------------
# Pointed tool for memory (RFC 3000)
# ---------------------------------------------------------------------------
proc lookupMemory*(query: string, workspace: string = ""): string =
  ## Searches memory for relevant context. Used as a pointed step in plans.
  ## Returns summarized memory relevant to the query.
  let memDir = if workspace.len > 0: workspace / ".nimo" / "memory" else: expandTilde("~/.nimo") / "memory"
  let memPath = memDir / "memories.json"
  
  if not fileExists(memPath):
    return ""
  
  try:
    let j = parseJson(readFile(memPath))
    var results: seq[string] = @[]
    for entry in j["entries"]:
      if entry.hasKey("text") and entry.hasKey("category"):
        results.add(entry["text"].getStr())
    
    # Simple relevance scoring (could be improved with embeddings)
    var scored: seq[(string, int)] = @[]
    let queryWords = query.toLowerAscii().splitWhitespace()
    for r in results:
      let rLower = r.toLowerAscii()
      var score = 0
      for w in queryWords:
        if w in rLower: inc score
      scored.add((r, score))
    
    # Sort by score descending (bubble sort for simplicity)
    for i in 0 ..< scored.len:
      for j in i+1 ..< scored.len:
        if scored[j][1] > scored[i][1]:
          let tmp = scored[i]
          scored[i] = scored[j]
          scored[j] = tmp
    
    var context = ""
    var tokenCount = 0
    for (text, score) in scored:
      if score > 0 and tokenCount + text.len < 500:
        context.add(text & "\n")
        tokenCount += text.len
    
    return context.strip()
  except:
    return ""
