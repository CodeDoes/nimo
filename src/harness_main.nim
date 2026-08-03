## NIMO Harness CLI entry point.
## Usage: harness [model.bin [vocab.txt]]
## Config: nimo.json (see src/config.nim) or NIMO_* env vars.
## Build with `-d:harnessOffline` to run without a model (generation is a stub).

import std/[os]
import ./harness, ./config

proc main() =
  var cfg = loadConfig()
  if paramCount() > 0:
    cfg.modelPath = paramStr(1)
  if paramCount() > 1:
    cfg.vocabPath = paramStr(2)
  let cwd = getCurrentDir()
  runHarnessCli(cfg, cwd)

when isMainModule:
  main()