## System Instructions for NIMO
## Manages system prompts and instructions for different workloads.

import std/[strutils, os, times, json, strformat]
import ./config

type
  SystemInstruction* = ref object
    id*: string
    timestamp*: string
    name*: string
    content*: string
    workload*: string  # chat, story, pipeline
    priority*: int

  InstructionSet* = ref object
    instructions*: seq[SystemInstruction]
    defaultInstruction*: string

const
  DefaultChatInstruction* = """You are a helpful AI assistant. Respond concisely and accurately."""
  DefaultStoryInstruction* = """You are a creative writing assistant. Write engaging stories with vivid descriptions and dynamic dialogue."""
  DefaultPipelineInstruction* = """You are a task automation assistant. Execute pipelines efficiently and report progress."""

proc newInstructionSet*(): InstructionSet =
  result = InstructionSet.new()
  result.instructions = @[]
  result.defaultInstruction = DefaultChatInstruction

proc addInstruction*(s: var InstructionSet, name: string, content: string, workload: string = "general", priority: int = 5) =
  let id = "instr_" & now().format("yyyyMMddHHmmss") & "_" & $s.instructions.len
  s.instructions.add(SystemInstruction(
    id: id,
    timestamp: now().format("yyyy-MM-dd HH:mm:ss"),
    name: name,
    content: content,
    workload: workload,
    priority: priority
  ))

proc getInstruction*(s: InstructionSet, workload: string): string =
  ## Gets the highest priority instruction for a workload.
  var bestInstruction = s.defaultInstruction
  var bestPriority = -1
  
  for instr in s.instructions:
    if instr.workload == workload or instr.workload == "general":
      if instr.priority > bestPriority:
        bestPriority = instr.priority
        bestInstruction = instr.content
  
  return bestInstruction

proc getDefaultInstruction*(): string =
  return DefaultChatInstruction

proc saveInstructions*(s: InstructionSet, path: string) =
  let dir = parentDir(path)
  if dir.len > 0 and dir != ".":
    createDir(dir)
  
  var j = newJObject()
  j["default"] = %s.defaultInstruction
  
  var instructions = newJArray()
  for instr in s.instructions:
    var ij = newJObject()
    ij["id"] = %instr.id
    ij["name"] = %instr.name
    ij["content"] = %instr.content
    ij["workload"] = %instr.workload
    ij["priority"] = %instr.priority
    instructions.add(ij)
  j["instructions"] = instructions
  
  writeFile(path, $j)

proc loadInstructions*(s: var InstructionSet, path: string): bool =
  if not fileExists(path):
    return false
  
  try:
    let j = parseJson(readFile(path))
    if "default" in j:
      s.defaultInstruction = j["default"].str
    
    s.instructions = @[]
    if "instructions" in j:
      for ij in j["instructions"]:
        s.instructions.add(SystemInstruction(
          id: ij["id"].str,
          timestamp: ij["timestamp"].str,
          name: ij["name"].str,
          content: ij["content"].str,
          workload: ij["workload"].str,
          priority: ij["priority"].getInt(5)
        ))
    return true
  except:
    return false

proc formatInstructions*(s: InstructionSet): string =
  var result = "=== System Instructions ===\n\n"
  result.add(&"Default: {s.defaultInstruction[0 ..< min(80, s.defaultInstruction.len)]}...\n\n")
  
  for instr in s.instructions:
    result.add(&"[{instr.name}] ({instr.workload}, priority {instr.priority})\n")
    result.add(&"  {instr.content[0 ..< min(60, instr.content.len)]}...\n\n")
  
  return result.strip()
