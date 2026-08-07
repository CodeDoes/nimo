## haiku.nims — Generate a haiku about AI
## Demonstrates the observable workflow.
## Run with: nim nimscripts scripts/haiku.nims

import std/[strutils]

const
  Prompt = "write a haiku about AI"
  OutputFile = "haiku.md"
  Schema = "Haiku"

proc main() =
  echo "=== Haiku Generator ==="
  echo "Prompt: " & Prompt
  echo "Schema: " & Schema
  echo ""
  
  # Simulate generate() call
  let output = """{"lines": ["bits of light", "thinking in silicon", "quiet minds"], "wordCount": 5}"""
  
  # Observable event (this is what gets logged)
  let event = """{
    "id": "gen_001",
    "timestamp": "2024-01-15T10:30:00",
    "prompt": """ & Prompt & """,
    "output": """ & output & """,
    "elapsed": 1.234,
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
  echo "Saved to: " & OutputFile

when isMainModule:
  main()
