## Simple Pipeline Tool for NIMO
## Implements a basic pipeline that can be called by the model.

import std/[json, os, times, strutils]
import ./session_manager, ./config  # config provides GenerateFn

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

proc generateStep*(pipeline: var Pipeline, session: var session_manager.Session, name: string, prompt: string, target: string = "", temp: float32 = DefaultTemp, topP: float32 = DefaultTopP, generate: GenerateFn = nil): string =
  ## Generate content for a pipeline step
  let stepId = pipeline.addStep(name, target)
  pipeline.startStep(stepId)
  
  try:
    let reply = session.generateTurn(name & ": " & prompt, generate, temp, topP)
    
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

proc summarizeStep*(pipeline: var Pipeline, session: var session_manager.Session, name: string, input: string, length: string = "brief", generate: GenerateFn = nil): string =
  ## Summarize content for a pipeline step
  let stepId = pipeline.addStep(name)
  pipeline.startStep(stepId)
  
  try:
    let prompt = "Summarize the following text (" & length & "): " & input
    let reply = session.generateTurn(prompt, generate)
    pipeline.completeStep(stepId, reply)
    return stepId
  except:
    pipeline.failStep(stepId, "Summarization failed")
    return stepId

proc extractStep*(pipeline: var Pipeline, session: var session_manager.Session, name: string, input: string, filter: string, generate: GenerateFn = nil): string =
  ## Extract specific content from input
  let stepId = pipeline.addStep(name)
  pipeline.startStep(stepId)
  
  try:
    let prompt = "Extract the following from the text: " & filter & "\n\nText: " & input
    let reply = session.generateTurn(prompt, generate)
    pipeline.completeStep(stepId, reply)
    return stepId
  except:
    pipeline.failStep(stepId, "Extraction failed")
    return stepId

proc pipelineTool*(session: var session_manager.Session, arguments: string, generate: GenerateFn = nil): string =
  ## Tool handler for run_pipeline — generates content and writes it to a file
  ## in the session's workspace (.nimo pipeline state + a named target file).
  ##
  ## Arguments JSON may carry:
  ##   {"intent": "...", "target": "NOTES.md"}
  ## If no target is given, writes to `output.md` under the workspace.
  var args: JsonNode
  try:
    args = parseJson(arguments)
  except:
    return "{\"error\": \"Invalid JSON arguments\"}"

  let intent = if "intent" in args and args["intent"].kind == JString:
                 args["intent"].str
               elif "prompt" in args and args["prompt"].kind == JString:
                 args["prompt"].str
               else: "unknown task"

  # Workspace-relative output target (sanitized to a bare filename).
  var target = "output.md"
  if "target" in args and args["target"].kind == JString:
    let t = args["target"].str.strip()
    if t.len > 0:
      target = t
  if "file" in args and args["file"].kind == JString and args["file"].str.strip().len > 0:
    target = args["file"].str.strip()

  # Create a new pipeline
  var pipeline = newPipeline()

  # Add steps based on intent (simplified for MVP)
  discard pipeline.generateStep(session, "Generate", intent, target = target, generate = generate)

  # Complete pipeline
  pipeline.finishPipeline()

  # Save pipeline state + write the produced content to the target file.
  let wsRoot = if session.cwd.len > 0: session.cwd else: "."
  let pipelineFile = wsRoot / ".nimo" / (pipeline.id & ".json")
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

  # Write the generated content to the requested target file.
  var wroteTarget = false
  for step in pipeline.steps:
    if step.target.len > 0 and step.output.len > 0:
      let absTarget =
        if isAbsolute(step.target): step.target
        else: wsRoot / step.target
      let d = parentDir(absTarget)
      if d.len > 0 and d != "." and not dirExists(d):
        createDir(d)
      writeFile(absTarget, step.output)
      wroteTarget = true
      target = absTarget

  let written = if wroteTarget: " -> " & target else: ""
  return "[nimo] Pipeline " & pipeline.id & " completed with " & $pipeline.steps.len &
         " steps; " & (if wroteTarget: "wrote target " & target else: "no target written")
