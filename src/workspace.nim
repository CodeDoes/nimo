## Workspace Management for NIMO
## Implements RFC 5000/3300: workspace creation, listing, switching.

import std/[os, strutils, times, json, parsejson]
import ./config

const
  DefaultWorkspaceDir = "~/.ws"
  WorkspaceConfigName = "config.toml"
  WikiDirName = "wiki"
  ChaptersDirName = "chapters"
  SessionsDirName = "sessions"
  OutlineFileName = "outline.md"
  NimoDirName = ".nimo"

type
  Workspace* = ref object
    path*: string
    name*: string
    created*: string
    isActive*: bool
    config*: NimoConfig

proc nowTimestamp*(): string =
  now().format("yyyyMMddHHmmss")

proc newWorkspace*(name: string, baseDir: string = DefaultWorkspaceDir): Workspace =
  ## Creates a new workspace with standard directory structure.
  result = Workspace.new()
  result.name = name
  let ts = nowTimestamp()
  # Expand `~` so dirs land in HOME rather than a literal `./~` in the cwd.
  result.path = expandTilde(baseDir) / name
  result.created = ts
  result.isActive = false

  # Create directory structure
  createDir(result.path)
  createDir(result.path / WikiDirName)
  createDir(result.path / ChaptersDirName)
  createDir(result.path / SessionsDirName)
  createDir(result.path / NimoDirName)
  createDir(result.path / NimoDirName / "model-cache")
  createDir(result.path / NimoDirName / "state-cache")

  # Write default config
  let configContent = """# NIMO Workspace Configuration
# Generated: """ & ts & """

[model]
model = "models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin"
vocab = "rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt"

[generation]
temperature = 0.7
topP = 0.7
maxTokens = 200
backend = "cuda"
gpuLayers = 99

[workspace]
name = """ & name & """
mode = "dev"

[story]
defaultGenre = "cyberpunk"
minChapterWords = 500
minParagraphs = 5
maxRepeats = 3

[pipeline]
maxIterations = 8
critiqueRounds = 3
"""
  writeFile(result.path / WorkspaceConfigName, configContent)

  # Write default outline
  let outlineContent = """# Story Outline: """ & name & """

## Title
[TBD]

## Logline
[TBD]

## Characters
### Main Characters
- [Character 1]

### Supporting Characters
- [Character 2]

## World/Setting
[TBD]

## Plot Summary
[TBD]

## Chapter Outline
### Chapter 1: [TBD]
- Setup
- Inciting Incident

### Chapter 2: [TBD]
- Rising Action

### Chapter 3: [TBD]
- Climax

### Chapter 4: [TBD]
- Falling Action

### Chapter 5: [TBD]
- Resolution

## Themes
- [Theme 1]
- [Theme 2]

## Notes
[Additional notes]
"""
  writeFile(result.path / OutlineFileName, outlineContent)

proc saveWorkspace*(w: Workspace, path: string) =
  ## Saves workspace metadata to a JSON file.
  var j = newJObject()
  j["name"] = %w.name
  j["path"] = %w.path
  j["created"] = %w.created
  j["isActive"] = %w.isActive
  writeFile(path, $j)

proc loadWorkspace*(path: string): Workspace =
  ## Loads a workspace from path.
  result = Workspace.new()
  result.path = path
  result.name = path.splitPath().tail.splitPath().tail
  result.isActive = true
  
  # Load config if exists
  let configPath = path / WorkspaceConfigName
  if fileExists(configPath):
    try:
      result.config = loadConfig(configPath)
    except:
      result.config = defaultConfig()
  else:
    result.config = defaultConfig()

proc listWorkspaces*(baseDir: string = DefaultWorkspaceDir): seq[Workspace] =
  ## Lists all workspaces in the base directory.
  result = @[]
  let expanded = expandTilde(baseDir)
  if not dirExists(expanded):
    return
  
  for entry in walkDir(expanded):
    let name = entry.path.splitPath().tail
    let wsPath = expanded / name
    let configPath = wsPath / WorkspaceConfigName
    if fileExists(configPath):
      try:
        result.add(loadWorkspace(wsPath))
      except:
        discard

proc findWorkspace*(nameOrPath: string, baseDir: string = DefaultWorkspaceDir): Workspace =
  ## Finds a workspace by name or path.
  # Try as path first
  let fullPath = expandTilde(nameOrPath)
  if dirExists(fullPath):
    return loadWorkspace(fullPath)
  
  # Try as name
  let expanded = expandTilde(baseDir)
  let candidate = expanded / nameOrPath
  if dirExists(candidate):
    return loadWorkspace(candidate)
  
  raise newException(KeyError, "Workspace not found: " & nameOrPath)

proc workspaceStatus*(ws: Workspace) =
  ## Prints workspace status information.
  echo "Workspace: " & ws.name
  echo "Path: " & ws.path
  echo "Created: " & ws.created
  echo "Active: " & $ws.isActive
  echo ""
  echo "Directories:"
  for dir in [WikiDirName, ChaptersDirName, SessionsDirName, NimoDirName]:
    let fullDir = ws.path / dir
    var count = 0
    if dirExists(fullDir):
      for _ in walkDir(fullDir):
        inc count
    echo "  " & dir & "/ (" & $count & " items)"

proc initWorkspace*(name: string, baseDir: string = DefaultWorkspaceDir, setActive: bool = false): Workspace =
  ## Creates and optionally activates a workspace.
  let ws = newWorkspace(name, baseDir)
  if setActive:
    # setDefaultWorkspace(ws.path)  # TODO: implement
    discard
  return ws

proc setDefaultWorkspace*(path: string) =
  ## Sets the default workspace for the current directory.
  let rcPath = getCurrentDir() / ".nimo-workspace"
  writeFile(rcPath, path)

proc getDefaultWorkspace*(): string =
  ## Gets the default workspace for the current directory.
  let rcPath = getCurrentDir() / ".nimo-workspace"
  if fileExists(rcPath):
    return readFile(rcPath).strip()
  return ""

proc removeWorkspace*(nameOrPath: string, baseDir: string = DefaultWorkspaceDir): bool =
  ## Removes a workspace directory.
  let ws = findWorkspace(nameOrPath, baseDir)
  try:
    removeDir(ws.path)
    return true
  except:
    return false

proc createWikiEntry*(ws: Workspace, name: string, content: string) =
  ## Creates a wiki entry file.
  let filename = name.toLowerAscii().replace(" ", "_") & ".md"
  let filepath = ws.path / WikiDirName / filename
  let header = "# " & name & "\n\n"
  writeFile(filepath, header & content)

proc createChapter*(ws: Workspace, number: int, title: string, content: string) =
  ## Creates a chapter file.
  let numStr = if number < 10: "0" & $number else: $number
  let filename = numStr & "_" & title.toLowerAscii().replace(" ", "_") & ".md"
  let filepath = ws.path / ChaptersDirName / filename
  let header = "# Chapter " & $number & ": " & title & "\n\n"
  writeFile(filepath, header & content)

proc readChapter*(ws: Workspace, number: int): string =
  ## Reads a chapter file by number.
  let numStr = if number < 10: "0" & $number else: $number
  let dir = ws.path / ChaptersDirName
  if not dirExists(dir): return ""
  for entry in walkDir(dir):
    let fname = entry.path.splitPath().tail
    if fname.startsWith(numStr & "_"):
      return readFile(entry.path)
  return ""

proc listChapters*(ws: Workspace): seq[string] =
  ## Lists all chapter files.
  result = @[]
  let dir = ws.path / ChaptersDirName
  if not dirExists(dir): return
  for entry in walkDir(dir):
    let fname = entry.path.splitPath().tail
    if fname.endsWith(".md"):
      result.add(fname)
