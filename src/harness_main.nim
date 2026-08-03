## NIMO Harness CLI entry point.
## Usage: harness [model.bin [vocab.txt]]
## Build with `-d:harnessOffline` to run without a model (generation is a stub).

import std/[os, strutils]
import ./harness, ./config

proc main() =
  let modelPath = if paramCount() > 0: paramStr(1) else: HarnessDefaultModel
  let vocabPath = if paramCount() > 1: paramStr(2) else: HarnessDefaultVocab
  let cwd = getCurrentDir()
  runHarnessCli(modelPath, vocabPath, cwd)

when isMainModule:
  main()