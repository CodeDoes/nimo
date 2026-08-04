import std/[os, strutils, osproc, times, strformat, sequtils]
import ./config, ./workspace, ./story, ./bootstrap, ./orchestrator, ./program, ./engine, ./harness


# ---------------------------------------------------------------------------
# Goal-first CLI commands (RFC 2000)
# ---------------------------------------------------------------------------
proc cmdPlanner(rest: seq[string]): int =
  ## `nimo planner "<goal>"` — compile a natural-language goal into a plan
  ## and show the steps. Deterministic, no model needed.
  if rest.len == 0:
    echo """Usage: nimo planner "<goal>"

Shows the plan the orchestrator would create from your goal.
Example:
  nimo planner "create a story about a lighthouse"
"""
    return 1

  var goal = ""
  for i, a in rest:
    if i > 0: goal.add(" ")
    goal.add(a)
  let plan = interpret(goal)

  echo "[planner] Goal: " & plan.goal
  echo "[planner] Plan: " & plan.id
  echo "[planner] Steps:"
  for i, step in plan.steps:
    let kind = $step.kind
    let name = if step.name.len > 0: " (" & step.name & ")" else: ""
    echo "  " & $i & ". [" & kind & "]" & name
  echo "[planner] Status: " & $plan.status
  return 0

proc cmdPlan(rest: seq[string]): int =
  ## `nimo plan <goal>` — alias for planner (goal-first CLI)
  return cmdPlanner(rest)

## NIMO CLI entry point
## Usage: nimo <command> [args...]
## Commands: generate, quantize, harness, chat, bake, workspace, story, unit
##
## Phase 0 item 4: the CLI DELEGATES to library modules — workspace.nim and
## story.nim hold the logic; this file only parses args and calls their
## functions. (Standalone tool binaries like generate/quantize/chat/harness
## are spawned because each owns its own arg parse + bootstrap — see
## rfc/2000-cli.md "Conceptual only".)

proc resolveWorkspace*(nameOrPath: string = ""): Workspace =
  ## Resolves the workspace for a story/workspace command: explicit name/path
  ## first, then the default for the current directory, else a fresh untitled
  ## workspace (which becomes the default).
  if nameOrPath.len > 0:
    return findWorkspace(nameOrPath)
  let def = getDefaultWorkspace()
  if def.len > 0 and dirExists(def):
    return loadWorkspace(def)
  let ws = newWorkspace("untitled_" & now().format("yyyyMMddHHmmss"))
  setDefaultWorkspace(ws.path)
  return ws

proc cmdWorkspace(rest: seq[string]): int =
  if rest.len == 0:
    echo """Usage: nimo workspace <command> [args]

Commands:
  create [NAME] [--set-default]  Create new workspace
  list                           List all workspaces
  use <name|path>                Switch to workspace
  status                         Show workspace status
  remove <name|path>             Remove workspace"""
    return 1

  let wsCmd = rest[0].strip().toLowerAscii()
  let wsArgs = if rest.len > 1: rest[1 ..< rest.len] else: @[]
  try:
    case wsCmd
    of "create":
      let setNameDefault = "--set-default" in wsArgs
      # first positional that is not a known flag is the name
      var name = ""
      for a in wsArgs:
        if a.startsWith("--"): continue
        name = a
        break
      if name.len == 0:
        name = "untitled_" & now().format("yyyyMMddHHmmss")
      echo "[workspace] Creating workspace: " & name
      let ws = newWorkspace(name)
      if setNameDefault:
        setDefaultWorkspace(ws.path)
        echo "[workspace] Set as default for: " & getCurrentDir()
      echo "[workspace] Created: " & ws.path
    of "list":
      echo "[workspace] Available workspaces:"
      let wss = listWorkspaces()
      if wss.len == 0: echo "  (none)"
      for ws in wss:
        echo "  " & ws.name
    of "use":
      if wsArgs.len == 0:
        echo "Error: workspace name required"
        return 1
      let ws = findWorkspace(wsArgs[0])
      setDefaultWorkspace(ws.path)
      echo "[workspace] Switched to: " & ws.name
    of "status":
      let def = getDefaultWorkspace()
      if def.len > 0 and dirExists(def):
        workspaceStatus(loadWorkspace(def))
      else:
        echo "[workspace] No active workspace"
    of "remove":
      if wsArgs.len == 0:
        echo "Error: workspace name required"
        return 1
      if removeWorkspace(wsArgs[0]):
        echo "[workspace] Removed: " & wsArgs[0]
      else:
        echo "Error: workspace not found: " & wsArgs[0]
        return 1
    else:
      echo "Error: unknown workspace command '" & wsCmd & "'"
      return 1
  except CatchableError as e:
    echo "Error: " & e.msg
    return 1
  return 0

proc cmdStory(rest: seq[string]): int =
  if rest.len == 0:
    echo """Usage: nimo story <command> [args]

Commands:
  generate <premise> [--workspace <name>] [--chapters N]
  validate <chapter-file> [--workspace <name>]
  critique <chapter-file> [--workspace <name>]
  outline [--workspace <name>] [--premise <text>]"""
    return 1

  let storyCmd = rest[0].strip().toLowerAscii()
  let storyArgs = if rest.len > 1: rest[1 ..< rest.len] else: @[]

  # find --workspace / --premise / --chapters values in args
  proc flagVal(args: seq[string], flag: string): string =
    for i, a in args:
      if a == flag and i + 1 < args.len: return args[i + 1]
    return ""
  let wsName = flagVal(storyArgs, "--workspace")

  try:
    case storyCmd
    of "validate", "critique":
      if storyArgs.len == 0:
        echo "Error: chapter file required"
        return 1
      let content = readFile(storyArgs[0])
      if storyCmd == "validate":
        let v = validateChapter(content)
        echo "[story] Chapter: " & v.title
        echo "[story] " & $v.wordCount & " words, " & $v.paragraphCount &
             " paragraphs, " & $v.repeatingSegments & " repeating segments"
        echo "[story] Quality: " & $v.quality
        for issue in v.issues:
          echo "  - " & issue
        return if v.quality == sqPass: 0 else: 1
      else:
        let c = critiqueChapter(content, 0)
        echo "[story] Score: " & $c.score
        echo "[story] Strengths: " & c.strengths.join(", ")
        echo "[story] Weaknesses: " & c.weaknesses.join(", ")
        echo "[story] Suggestions: " & c.suggestions.join(", ")
        return if c.shouldRevise: 1 else: 0
    of "outline", "generate":
      # Needs the real model: one bootstrap, then delegate to story.nim.
      if storyCmd == "generate" and storyArgs.len == 0:
        echo "Error: premise required"
        return 1
      let cfg = loadConfig()
      let bs = bootstrapSession(cfg, getCurrentDir())
      for line in bs.lines: echo line
      if not bs.ok: return 1
      var s = bs.session
      let ws = resolveWorkspace(wsName)
      if storyCmd == "outline":
        let premise = flagVal(storyArgs, "--premise")
        echo "[story] Generating outline for workspace " & ws.name & "..."
        let outline = generateOutline(s, premise)
        writeFile(ws.path / "outline.md", outline)
        echo "[story] Outline saved to " & ws.path / "outline.md"
      else:
        let premise = storyArgs[0]
        var chapters = 5
        let chStr = flagVal(storyArgs, "--chapters")
        if chStr.len > 0: chapters = parseInt(chStr)
        echo "[story] Running story pipeline for workspace " & ws.name & "..."
        if runStoryPipeline(ws, s, premise, chapters):
          echo "[story] Story complete."
        else:
          echo "[story] Pipeline finished with revisions pending."
      return 0
    else:
      echo "Error: unknown story command '" & storyCmd & "'"
      return 1
  except CatchableError as e:
    echo "Error: " & e.msg
    return 1


proc cmdRun(rest: seq[string]): int =
  ## `nimo run <plan_path>` — execute a plan through the engine
  if rest.len == 0:
    echo """Usage: nimo run <plan_path> [--resume]

Execute a plan artifact through the engine.
Example:
  nimo run .nimo/programs/myplan.json
  nimo run .nimo/programs/myplan.json --resume
"""
    return 1

  let planPath = rest[0]
  let resume = "--resume" in rest

  if not fileExists(planPath):
    echo "Error: plan not found: " & planPath
    return 1

  var plan = loadPlan(planPath)
  echo "[run] Plan: " & plan.id
  echo "[run] Goal: " & plan.goal
  echo "[run] Steps: " & $plan.steps.len
  
  # Execute through engine with a placeholder generator
  # (Full model integration: bootstrap session, wire generateTurn)
  var sinkText = ""
  let gen: GenerateFn = proc(prompt: string): string =
    "[stub] " & prompt
  let result = plan.run(gen, sink = proc(t: string) = sinkText.add(t), maxSteps = 256)
  
  echo "[run] Completed: " & $result.completed
  echo "[run] Steps run: " & $result.stepsRun
  if sinkText.len > 0:
    echo "[run] Output:"
    echo sinkText
  return 0

proc cmdNew(rest: seq[string]): int =
  ## `nimo new <goal>` — open a session, compile goal, run plan
  if rest.len == 0:
    echo """Usage: nimo new "<goal>"

Open a session and run the plan for your goal.
Example:
  nimo new "create a story about a lighthouse"
"""
    return 1

  let goal = rest.join(" ")
  let plan = interpret(goal)

  echo "[new] Goal: " & plan.goal
  echo "[new] Plan: " & plan.id
  echo "[new] Steps:"
  for i, step in plan.steps:
    echo "  " & $i & ". [" & $step.kind & "] " & step.name

  # Save plan
  let programsDir = getCurrentDir() / ".nimo" / "programs"
  createDir(programsDir)
  let planPath = programsDir / (plan.id & ".json")
  plan.save(planPath)
  echo "[new] Saved: " & planPath

  echo "[new] To run: nimo run " & planPath
  return 0


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
  planner      Show plan for a goal
  new          Create session from goal
  run          Execute a plan
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
  of "planner", "plan":
    quit(cmdPlanner(rest))
  of "run":
    quit(cmdRun(rest))
  of "new":
    quit(cmdNew(rest))
  of "workspace":
    quit(cmdWorkspace(rest))
  of "story":
    quit(cmdStory(rest))
  of "unit", "eval":
    let binary = baseDir / "unit"
    if fileExists(binary):
      quit(execCmd(binary))
    else:
      echo "Error: unit binary not found. Run 'nimble build' first."
      quit(1)
  else:
    echo "Error: unknown command '" & cmd & "'"
    echo "Run 'nimo' without arguments for help."
    quit(1)

when isMainModule:
  main()

# ---------------------------------------------------------------------------
# Session commands (nimo new, nimo run)
# ---------------------------------------------------------------------------
when isMainModule:
  main()
