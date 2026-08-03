## NIMO Harness CLI entry point.
## Subcommands: chat (default), generate, bake
## Usage:
##   harness chat [OPTIONS] [MODEL] [VOCAB]
##   harness generate [OPTIONS] PROMPT [MODEL] [VOCAB]
##   harness bake [OPTIONS] PROMPT [MODEL] [STATE] [VOCAB]
## Config: nimo.json (see src/config.nim) or NIMO_* env vars.
## Build with `-d:harnessOffline` to run without a model (generation is a stub).

import std/[os, strutils, osproc]
import ./harness, ./config

proc main() =
  let rawCmd = if paramCount() > 0: paramStr(1).strip().toLowerAscii() else: "chat"

  if rawCmd == "generate":
    var newArgs = newSeq[string]()
    for i in 2 .. paramCount():
      newArgs.add(paramStr(i))
    discard execCmd("./build/generate " & newArgs.join(" "))
  elif rawCmd == "bake":
    var newArgs = newSeq[string]()
    for i in 2 .. paramCount():
      newArgs.add(paramStr(i))
    discard execCmd("./build/bake_state " & newArgs.join(" "))
  else:
    # Default: chat mode
    var cfg = loadConfig()
    if paramCount() > 1: cfg.modelPath = paramStr(2)
    if paramCount() > 2: cfg.vocabPath = paramStr(3)
    let cwd = getCurrentDir()
    runHarnessCli(cfg, cwd)

when isMainModule:
  main()
