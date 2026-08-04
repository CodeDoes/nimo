## NIMO CLI entry point
## Usage: nimo <command> [args...]
## Commands: generate, quantize, harness, chat, bake, workspace, story, eval

import std/[os, strutils, osproc, times]

proc main() =
  let args = commandLineParams()
  if args.len == 0:
    echo """nimo -- RWKV inference CLI

Commands:
  generate     Generate text from a prompt
  quantize     Convert model quantization
  harness      Interactive chat harness
  chat         Simple chat
  bake         Bake model state
  workspace    Workspace management
  story        Story pipeline
  unit         Run the unit test suite
  eval         (alias) Run the unit test suite
  model-eval   Run model behavior evals (planned)

Usage:
  nimo generate --backend cuda --model <path> --prompt "Hello"
  nimo quantize <input> <format> <output>
  nimo harness
  nimo chat --backend cuda <model>
  nimo workspace create <name>
  nimo story generate <premise> --workspace <name>
  nimo unit
"""
    quit(0)

  let cmd = args[0].strip().toLowerAscii()
  let rest = if args.len > 1: args[1 ..< args.len] else: @[]
  let baseDir = getCurrentDir() / "build"

  case cmd
  of "generate":
    let binary = baseDir / "generate"
    var cmdLine = binary & " " & rest.join(" ")
    if execCmd(cmdLine) != 0: quit(1)
  of "quantize":
    let binary = baseDir / "quantize"
    var cmdLine = binary & " " & rest.join(" ")
    if execCmd(cmdLine) != 0: quit(1)
  of "harness":
    let binary = baseDir / "harness"
    var cmdLine = binary & " " & rest.join(" ")
    if execCmd(cmdLine) != 0: quit(1)
  of "chat":
    let binary = baseDir / "chat"
    var cmdLine = binary & " " & rest.join(" ")
    if execCmd(cmdLine) != 0: quit(1)
  of "bake":
    let binary = baseDir / "bake_state"
    var cmdLine = binary & " " & rest.join(" ")
    if execCmd(cmdLine) != 0: quit(1)
  of "workspace":
    if rest.len == 0:
      echo "Usage: nimo workspace <command> [args]"
      echo ""
      echo "Commands:"
      echo "  create [NAME] [--set-default]  Create new workspace"
      echo "  list                           List all workspaces"
      echo "  use <name|path>                Switch to workspace"
      echo "  status                         Show workspace status"
      echo "  remove <name|path>             Remove workspace"
      quit(0)
    
    let wsCmd = rest[0].strip().toLowerAscii()
    let wsArgs = if rest.len > 1: rest[1 ..< rest.len] else: @[]
    
    case wsCmd
    of "create":
      let setNameDefault = "--set-default" in wsArgs
      let wsName = if wsArgs.len > 0 and not setNameDefault: wsArgs[0] else: "untitled_" & now().format("yyyyMMddHHmmss")
      echo "[workspace] Creating workspace: " & wsName
      let wsPath = expandTilde("~/.ws") / wsName
      createDir(wsPath)
      createDir(wsPath / "wiki")
      createDir(wsPath / "chapters")
      createDir(wsPath / "sessions")
      createDir(wsPath / ".nimo")
      createDir(wsPath / ".nimo" / "model-cache")
      createDir(wsPath / ".nimo" / "state-cache")
      writeFile(wsPath / "config.toml", "# NIMO Workspace Config\nworkspace = \"" & wsName & "\"\n")
      writeFile(wsPath / "outline.md", "# " & wsName & "\n\n## Outline\n\n[TBD]\n")
      echo "[workspace] Created: " & wsPath
      if setNameDefault:
        writeFile(getCurrentDir() / ".nimo-workspace", wsPath)
        echo "[workspace] Set as default for: " & getCurrentDir()
    of "list":
      echo "[workspace] Available workspaces:"
      let wsDir = expandTilde("~/.ws")
      if dirExists(wsDir):
        for entry in walkDir(wsDir):
          let name = entry.path.splitPath().tail
          let configPath = entry.path / "config.toml"
          if fileExists(configPath):
            echo "  " & name
      else:
        echo "  (none)"
    of "use":
      if wsArgs.len == 0:
        echo "Error: workspace name required"
        quit(1)
      let wsPath = expandTilde("~/.ws") / wsArgs[0]
      if dirExists(wsPath):
        writeFile(getCurrentDir() / ".nimo-workspace", wsPath)
        echo "[workspace] Switched to: " & wsArgs[0]
      else:
        echo "Error: workspace not found: " & wsArgs[0]
        quit(1)
    of "status":
      let rcPath = getCurrentDir() / ".nimo-workspace"
      let wsPath = if fileExists(rcPath): readFile(rcPath).strip() else: ""
      if wsPath.len > 0 and dirExists(wsPath):
        echo "[workspace] Current: " & wsPath
        for d in ["wiki", "chapters", "sessions", ".nimo"]:
          let fullDir = wsPath / d
          var count = 0
          if dirExists(fullDir):
            for _ in walkDir(fullDir): inc count
          echo "  " & d & "/ (" & $count & " items)"
      else:
        echo "[workspace] No active workspace"
    of "remove":
      if wsArgs.len == 0:
        echo "Error: workspace name required"
        quit(1)
      let wsPath = expandTilde("~/.ws") / wsArgs[0]
      if dirExists(wsPath):
        removeDir(wsPath)
        echo "[workspace] Removed: " & wsArgs[0]
      else:
        echo "Error: workspace not found: " & wsArgs[0]
    else:
      echo "Error: unknown workspace command '" & wsCmd & "'"
      quit(1)
  of "story":
    if rest.len == 0:
      echo "Usage: nimo story <command> [args]"
      echo ""
      echo "Commands:"
      echo "  generate <premise> [--workspace <name>] [--chapters N]"
      echo "  validate <chapter> [--workspace <name>]"
      echo "  critique <chapter> [--workspace <name>]"
      echo "  outline [--workspace <name>]"
      quit(0)
    
    let storyCmd = rest[0].strip().toLowerAscii()
    let storyArgs = if rest.len > 1: rest[1 ..< rest.len] else: @[]
    
    case storyCmd
    of "generate":
      echo "[story] Generating story..."
      echo "[story] Use: nimo story generate <premise> --workspace <name>"
    of "validate":
      echo "[story] Validating chapter..."
    of "critique":
      echo "[story] Critiquing chapter..."
    of "outline":
      echo "[story] Generating outline..."
    else:
      echo "Error: unknown story command '" & storyCmd & "'"
      quit(1)
  of "unit", "eval":
    let binary = baseDir / "unit"
    if fileExists(binary):
      let rc = execCmd(binary)
      quit(rc)
    else:
      echo "Error: unit binary not found. Run 'nimble build' first."
      quit(1)
  else:
    echo "Error: unknown command '" & cmd & "'"
    echo "Run 'nimo' without arguments for help."
    quit(1)

when isMainModule:
  main()
