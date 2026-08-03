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
                metadata: dict[string, string] = @[]): string =
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
