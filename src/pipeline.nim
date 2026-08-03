## Simple Pipeline Tool for NIMO
## Implements a basic pipeline that can be called by the model.

import std/[json, strutils, os, times]
import ./session_manager, ./config

type
  PipelineStep* = object
    id*: string
    name*: string
    status*: string  # pending, running, completed, failed
    output*: string
    target*: string

  PipelineNode* = ref object
    id*: string
    prompt*: string
    target*: string
    output*: string
    dependencies*: seq[string]

  Pipeline* = ref object
    id*: string
    timestamp*: string
    steps*: seq[PipelineStep]
    nodes*: seq[PipelineNode]
    status*: string  # running, completed, failed, interrupted

proc newPipeline*(): Pipeline =
  result = Pipeline.new()
  result.id = "pipe_" & now().format("yyyyMMddHHmmss")
  result.timestamp = nowStr()
  result.status = "running"

proc addStep*(p: var Pipeline, name: string, target: string = ""): string =
  let stepId = "step_" & $p.steps.len
  p.steps.add(PipelineStep(
    id: stepId,
    name: name,
    status: "pending",
    target: target
  ))
  return stepId

proc startStep*(p: var Pipeline, stepId: string) =
  for i in 0 ..< p.steps.len:
    if p.steps[i].id == stepId:
      p.steps[i].status = "running"
      break

proc completeStep*(p: var Pipeline, stepId: string, output: string) =
  for i in 0 ..< p.steps.len:
    if p.steps[i].id == stepId:
      p.steps[i].status = "completed"
      p.steps[i].output = output
      break

proc failStep*(p: var Pipeline, stepId: string, error: string) =
  for i in 0 ..< p.steps.len:
    if p.steps[i].id == stepId:
      p.steps[i].status = "failed"
      p.steps[i].output = error
      break

proc finishPipeline*(p: var Pipeline, status: string = "completed") =
  p.status = status

proc generateStep*(pipeline: var Pipeline, session: var session_manager.Session, name: string, prompt: string, target: string = "", temp: float32 = DefaultTemp, topP: float32 = DefaultTopP): string =
  ## Generate content for a pipeline step
  let stepId = pipeline.addStep(name, target)
  pipeline.startStep(stepId)
  
  try:
    let reply = session.generateTurn(name & ": " & prompt, temp, topP)
    
    pipeline.completeStep(stepId, reply)
    
    # Write to target if specified
    if target.len > 0:
      let dir = parentDir(target)
      if dir.len > 0 and dir != ".":
        createDir(dir)
      writeFile(target, reply)
    
    return stepId
  except:
    pipeline.failStep(stepId, "Generation failed")
    return stepId

proc summarizeStep*(pipeline: var Pipeline, session: var session_manager.Session, name: string, input: string, length: string = "brief"): string =
  ## Summarize content for a pipeline step
  let stepId = pipeline.addStep(name)
  pipeline.startStep(stepId)
  
  try:
    let prompt = "Summarize the following text (" & length & "): " & input
    let reply = session.generateTurn(prompt)
    pipeline.completeStep(stepId, reply)
    return stepId
  except:
    pipeline.failStep(stepId, "Summarization failed")
    return stepId

proc extractStep*(pipeline: var Pipeline, session: var session_manager.Session, name: string, input: string, filter: string): string =
  ## Extract specific content from input
  let stepId = pipeline.addStep(name)
  pipeline.startStep(stepId)
  
  try:
    let prompt = "Extract the following from the text: " & filter & "\n\nText: " & input
    let reply = session.generateTurn(prompt)
    pipeline.completeStep(stepId, reply)
    return stepId
  except:
    pipeline.failStep(stepId, "Extraction failed")
    return stepId

proc pipelineTool*(session: var session_manager.Session, arguments: string): string =
  ## Tool handler for run_pipeline
  var args: JsonNode
  try:
    args = parseJson(arguments)
  except:
    return "{\"error\": \"Invalid JSON arguments\"}"
  
  let intent = if "intent" in args: args["intent"].str else: "unknown task"
  
  # Create a new pipeline
  var pipeline = newPipeline()
  
  # Add steps based on intent (simplified for MVP)
  discard pipeline.generateStep(session, "Generate", intent, target = "output.txt")
  
  # Complete pipeline
  pipeline.finishPipeline()
  
  # Save pipeline state
  let pipelineFile = session.cwd & "/.nimo/" & pipeline.id & ".json"
  createDir(parentDir(pipelineFile))
  var j = newJObject()
  j["id"] = %pipeline.id
  j["status"] = %pipeline.status
  j["timestamp"] = %pipeline.timestamp
  var steps = newJArray()
  for step in pipeline.steps:
    var s = newJObject()
    s["id"] = %step.id
    s["name"] = %step.name
    s["status"] = %step.status
    s["output"] = %step.output
    steps.add(s)
  j["steps"] = steps
  writeFile(pipelineFile, j.pretty)
  
  return "[nimo] Pipeline " & pipeline.id & " completed with " & $pipeline.steps.len & " steps"
