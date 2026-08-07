## haiku.nim - Generate haikus about AI using the real model
## Demonstrates the observable workflow with real inference.
## Usage: LD_LIBRARY_PATH="rwkv.cpp:rwkv.cpp/ggml/src:$LD_LIBRARY_PATH" nimble haiku -- --use-default-prompt
##        LD_LIBRARY_PATH="rwkv.cpp:rwkv.cpp/ggml/src:$LD_LIBRARY_PATH" nimble haiku -- "write a haiku about X"

import std/[times, os, json]
import ../src/config, ../src/bootstrap, ../src/session_manager

const
  DefaultPrompts = @["write a haiku about AI", "write a haiku about robots", "write a haiku about code"]
  OutputDir = ".nimo/demos/haikus"
  OutputFile = OutputDir / "all_generated.jsonl"
  Schema = "Haiku"

proc main() =
  # Parse args
  var useDefaults = false
  var prompts: seq[string] = @[]
  
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg == "--use-default-prompt":
      useDefaults = true
    elif arg.startsWith("--"):
      echo "Error: unknown option: " & arg
      quit(1)
    else:
      prompts.add(arg)
  
  # Require either NL input or --use-default-prompt
  if prompts.len == 0 and not useDefaults:
    echo """Usage: nimble haiku -- "<prompt>" [more prompts...]
       nimble haiku -- --use-default-prompt

Examples:
  nimble haiku -- "write a haiku about AI"
  nimble haiku -- "write a haiku about AI" "robots love code"
  nimble haiku -- --use-default-prompt
"""
    quit(1)
  
  # Set prompts
  if useDefaults and prompts.len == 0:
    prompts = DefaultPrompts
  
  echo "=== Haiku Generator (Real Model) ==="
  echo "Prompts: " & $prompts.len
  echo ""
  
  # Create output directory
  if not dirExists(OutputDir):
    createDir(OutputDir)
  
  echo "Output dir: " & OutputDir
  echo "Output file: " & OutputFile
  echo "File exists before: " & $fileExists(OutputFile)
  
  # Load config
  let cfg = loadConfig()
  echo "Model: " & cfg.modelPath
  echo "Backend: " & $cfg.backend
  echo ""
  
  # Bootstrap session
  let bs = bootstrapSession(cfg, getCurrentDir())
  echo "Bootstrap ok: " & $bs.ok
  echo "Bootstrap stub: " & $bs.stub
  for line in bs.lines: echo "  " & line
  echo ""
  
  if not bs.ok:
    echo "ERROR: Failed to bootstrap session"
    quit(1)
  
  var s = bs.session
  
  # Open trace file (append mode)
  let f = open(OutputFile, fmAppend)
  defer: f.close()
  
  echo "File exists after open: " & $fileExists(OutputFile)
  
  var runId = now().format("yyyyMMddHHmmss")
  echo "Run ID: " & runId
  echo ""
  
  for i, prompt in prompts:
    echo "--- Haiku " & $(i + 1) & " ---"
    echo "Prompt: " & prompt
    echo ""
    
    let t0 = cpuTime()
    
    # Real generate call
    let output = s.generateTurn(prompt, bs.generate, cfg.temperature, cfg.topP, cfg.maxTokens)
    let elapsed = cpuTime() - t0
    
    # Observable event (JSONL)
    let event = newJObject()
    event["id"] = %("gen_" & runId & "_" & $i)
    event["timestamp"] = %(now().format("yyyy-MM-dd'T'HH:mm:ss"))
    event["prompt"] = %(prompt)
    event["output"] = %(output)
    event["elapsed"] = %(elapsed)
    event["tokensIn"] = %(8)
    event["tokensOut"] = %(output.len div 4)
    event["temperature"] = %(cfg.temperature)
    event["topP"] = %(cfg.topP)
    event["maxTokens"] = %(cfg.maxTokens)
    event["backend"] = %($cfg.backend)
    event["schema"] = %(Schema)
    event["step"] = %(i)
    event["planId"] = %("plan_" & runId)
    
    f.writeLine($event)
    f.flushFile()
    
    echo "Generated:"
    echo output
    echo ""
    echo "Elapsed: " & $elapsed & "s"
    echo ""
  
  echo "=== Complete ==="
  echo "Trace appended to: " & OutputFile
  echo "File exists after: " & $fileExists(OutputFile)

when isMainModule:
  main()
