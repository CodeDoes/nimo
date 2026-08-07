## haiku.nims — Generate a haiku about AI
## Demonstrates the observable workflow.
## Run with: nim nimscripts scripts/haiku.nims

import std/[strutils, times]

const
  Prompt = "write a haiku about AI"
  OutputFile = "haiku.md"
  Schema = "Haiku"

proc main() =
  echo "=== Haiku Generator ==="
  echo "Prompt: " & Prompt
  echo "Schema: " & Schema
  echo ""
  
  let t0 = cpuTime()
  
  # Simulate generate() call
  let output = """{"lines": ["bits of light", "thinking in silicon", "quiet minds"], "wordCount": 5}"""
  
  let elapsed = cpuTime() - t0
  
  # Observable event (this is what gets logged)
  let event = """{
    "id": "gen_001",
    "timestamp": """ & now().format("yyyy-MM-dd'T'HH:mm:ss") & """,
    "prompt": """ & Prompt & """,
    "output": """ & output & """,
    "elapsed": """ & $elapsed & """,
    "tokensIn": 8,
    "tokensOut": 12,
    "temperature": 0.7,
    "topP": 0.7,
    "maxTokens": 50,
    "backend": "cuda",
    "schema": """ & Schema & """,
    "step": 0,
    "planId": "plan_test"
  }"""
  
  echo "=== Generate Event ==="
  echo event
  echo ""
  echo "Generated:"
  echo output
  echo ""
  echo "Elapsed: " & $elapsed & "s"
  echo ""
  echo "Saved to: " & OutputFile

when isMainModule:
  main()
