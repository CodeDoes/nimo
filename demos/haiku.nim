## haiku.nim - Generate haikus about AI
## Demonstrates the observable workflow with batch generation.
## Accumulates traces across runs.
## Run with: nim c -o:build/haiku demos/haiku.nim && ./build/haiku

import std/[times, os, json, random]

const
  Prompts = @["write a haiku about AI", "write a haiku about robots", "write a haiku about code"]
  OutputDir = ".nimo/demos/haikus"
  OutputFile = OutputDir / "all_generated.jsonl"
  Schema = "Haiku"

proc randomHaiku(prompt: string): string =
  ## Generate a random haiku response
  let words = case rand(3)
    of 0: @["bits of light", "thinking in silicon", "quiet minds"]
    of 1: @["electric dreams", "binary rain", "silent thoughts"]
    else: @["metal hands", "coding dreams", "electric heart"]
  let wordCount = words.len
  result = "{\"lines\": [\"" & words[0] & "\", \"" & words[1] & "\", \"" & words[2] & "\"], \"wordCount\": " & $wordCount & "}"

proc main() =
  echo "=== Haiku Generator (Batch) ==="
  echo ""
  
  createDir(OutputDir)
  
  # Seed random with current time for variety
  randomize()
  
  # Open trace file (append mode)
  let f = open(OutputFile, fmAppend)
  defer: f.close()
  
  var runId = now().format("yyyyMMddHHmmss")
  echo "Run ID: " & runId
  echo ""
  
  for i, prompt in Prompts:
    echo "--- Haiku " & $(i + 1) & " ---"
    echo "Prompt: " & prompt
    echo ""
    
    let t0 = cpuTime()
    
    # Simulate generate() call with randomization
    let output = randomHaiku(prompt)
    let elapsed = cpuTime() - t0
    
    # Observable event (JSONL)
    let event = newJObject()
    event["id"] = %("gen_" & runId & "_" & $i)
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
    event["planId"] = %("plan_" & runId)
    
    f.writeLine($event)
    
    echo "Generated:"
    echo output
    echo ""
    echo "Elapsed: " & $elapsed & "s"
    echo ""
  
  echo "=== Complete ==="
  echo "Trace appended to: " & OutputFile

when isMainModule:
  main()
