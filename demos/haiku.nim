## haiku.nim — Generate haikus about AI
## Demonstrates the observable workflow with batch generation.
## Run with: nim c -o:build/haiku demos/haiku.nim && ./build/haiku

import std/[times, os, json]

const
  Prompts = @["write a haiku about AI", "write a haiku about robots", "write a haiku about code"]
  OutputDir = ".nimo/demos/haikus"
  OutputFile = OutputDir / "all_generated.jsonl"
  Schema = "Haiku"

proc main() =
  echo "=== Haiku Generator (Batch) ==="
  echo ""
  
  createDir(OutputDir)
  
  # Open trace file
  let f = open(OutputFile, fmWrite)
  defer: f.close()
  
  for i, prompt in Prompts:
    echo "--- Haiku """ & $(i + 1) & """ ---"
    echo "Prompt: " & prompt
    echo ""
    
    let t0 = cpuTime()
    
    # Simulate generate() call
    let outputs = @[
      """{"lines": ["bits of light", "thinking in silicon", "quiet minds"], "wordCount": 5}""",
      """{"lines": ["metal hands", "coding dreams", "electric heart"], "wordCount": 6}""",
      """{"lines": ["0 and 1", "flow like water", "logic flows"], "wordCount": 6}"""]
    
    let output = outputs[i]
    let elapsed = cpuTime() - t0
    
    # Observable event (JSONL)
    let event = newJObject()
    event["id"] = %("gen_" & $i)
    event["timestamp"] = %(now().format("yyyy-MM-dd'T'HH:mm:ss"))
    event["prompt"] = %(prompt)
    event["output"] = %(output)
    event["elapsed"] = %(elapsed)
    event["tokensIn"] = %(8)
    event["tokensOut"] = %(12)
    event["temperature"] = %(0.7)
    event["topP"] = %(0.7)
    event["maxTokens"] = %(50)
    event["backend"] = %("cuda")
    event["schema"] = %(Schema)
    event["step"] = %(i)
    event["planId"] = %("plan_test")
    
    f.writeLine($event)
    
    echo "Generated:"
    echo output
    echo ""
    echo "Elapsed: " & $elapsed & "s"
    echo ""
  
  echo "=== Complete ==="
  echo "Trace saved to: " & OutputFile

when isMainModule:
  main()
