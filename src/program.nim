## program.nim — The plan artifact (RFC 3500)
## Plan-as-data: a resumable, observable list of pointed Steps.
##
## The plan is what the orchestrator compiles and what the engine executes.
## Because it is DATA (JSON on disk), it is resumable (save + cursor),
## interruptible, observable (step statuses), and safe to edit by hand.
##
## This module is deterministic and offline-safe (no RWKV model import), so it
## is fully covered by the unit suite (nimo unit).

import std/[json, os, times, strutils]

type
  StepKind* = enum
    skExtract          ## pull a focused slice (model lookup or memory)
    skSummarize        ## condense input to its essence
    skGenerate         ## the ONLY "thinking" step: uses an output-state
    skValidate         ## deterministic quality gate (words/paragraphs/repeats)
    skWrite            ## deterministic file output
    skLoop             ## fan out over an extracted list (data-driven)
    skReport           ## checkpoint visible to the user

  StepStatus* = enum
    ssPending, ssRunning, ssCompleted, ssFailed, ssSkipped

  Step* = object
    kind*: StepKind
    name*: string            # readable label (shown in the ▶/✔ trace)
    # Extract
    source*: string          # where to pull from: "outline", "memory", "wiki"
    filter*: string          # what to pull: "characters", "events for ch3", ...
    forWhom*: string         # who it's for: a character or chapter name
    # Summarize
    input*: string
    length*: string          # brief | medium | detailed
    # Generate
    skill*: string           # which output-state bake to use
    context*: string         # the focused slice to generate from
    # Write
    path*: string            # target file path
    content*: string         # output content (filled by execution)
    # Loop
    items*: string           # source expression for the list (e.g. "characters")
    # Report
    title*: string
    # runtime
    status*: StepStatus
    output*: string          # result of this step (filled by the engine)

  PlanStatus* = enum
    psRunning, psPaused, psDone, psInterrupted

  Plan* = ref object
    id*: string
    goal*: string
    cursor*: int             # next unexecuted step index (resume point)
    steps*: seq[Step]
    status*: PlanStatus
    timestamp*: string

proc nowStamp*(): string =
  now().format("yyyy-MM-dd'T'HH:mm:ss")

proc stepKindName*(k: StepKind): string =
  $k

# ---------------------------------------------------------------------------
# Construction helpers
# ---------------------------------------------------------------------------
proc newPlan*(goal: string): Plan =
  result = Plan()
  result.id = "plan_" & now().format("yyyyMMddHHmmss")
  result.goal = goal
  result.cursor = 0
  result.status = psRunning
  result.timestamp = nowStamp()

proc extractStep*(name, source: string, filter="", forWhom=""): Step =
  Step(kind: skExtract, name: name, source: source, filter: filter,
       forWhom: forWhom, status: ssPending)

proc summarizeStep*(name: string, input: string, length="brief"): Step =
  Step(kind: skSummarize, name: name, input: input, length: length,
       status: ssPending)

proc generateStep*(name, context: string, skill=""): Step =
  Step(kind: skGenerate, name: name, context: context, skill: skill,
       status: ssPending)

proc validateStep*(name, text: string): Step =
  Step(kind: skValidate, name: name, input: text, status: ssPending)

proc writeStep*(name, path: string, content=""): Step =
  Step(kind: skWrite, name: name, path: path, content: content,
       status: ssPending)

proc loopStep*(name, items: string): Step =
  Step(kind: skLoop, name: name, items: items, status: ssPending)

proc reportStep*(title: string): Step =
  Step(kind: skReport, name: title, title: title, status: ssPending)

# ---------------------------------------------------------------------------
# Plan navigation
# ---------------------------------------------------------------------------
proc addStep*(p: var Plan, s: Step) =
  p.steps.add(s)

proc currentStep*(p: Plan): ptr Step =
  ## The step at the plan cursor, or nil at end.
  if p.cursor >= 0 and p.cursor < p.steps.len:
    result = addr p.steps[p.cursor]

proc isDone*(p: Plan): bool =
  p.cursor >= p.steps.len

proc advance*(p: Plan) =
  ## Moves the cursor to the next step.
  if not p.isDone:
    inc p.cursor
  if p.isDone:
    p.status = psDone

proc splice*(p: var Plan, steps: seq[Step], at: int) =
  ## Inserts `steps` at index `at` (used by Loop / orchestrator to fan out).
  p.steps = p.steps[0 ..< at] & steps & p.steps[at .. ^1]
  if at < p.cursor:
    p.cursor += steps.len

proc checkpoint*(p: Plan): JsonNode =
  ## The resumable state: everything needed to continue from the cursor.
  result = newJObject()
  result["id"] = %p.id
  result["goal"] = %p.goal
  result["cursor"] = %p.cursor
  result["status"] = %($p.status)
  result["timestamp"] = %p.timestamp

# ---------------------------------------------------------------------------
# Persistence (compact JSON, one line per object)
# ---------------------------------------------------------------------------
proc stepToJson(s: Step): JsonNode =
  result = newJObject()
  result["kind"] = %($s.kind)
  if s.name.len > 0: result["name"] = %s.name
  if s.source.len > 0: result["source"] = %s.source
  if s.filter.len > 0: result["filter"] = %s.filter
  if s.forWhom.len > 0: result["for"] = %s.forWhom
  if s.input.len > 0: result["input"] = %s.input
  if s.length.len > 0: result["length"] = %s.length
  if s.skill.len > 0: result["skill"] = %s.skill
  if s.context.len > 0: result["context"] = %s.context
  if s.path.len > 0: result["path"] = %s.path
  if s.content.len > 0: result["content"] = %s.content
  if s.items.len > 0: result["items"] = %s.items
  if s.title.len > 0: result["title"] = %s.title
  result["status"] = %($s.status)
  if s.output.len > 0: result["output"] = %s.output

proc save*(p: Plan, path: string) =
  var j = newJObject()
  j["id"] = %p.id
  j["goal"] = %p.goal
  j["cursor"] = %p.cursor
  j["status"] = %($p.status)
  j["timestamp"] = %p.timestamp
  var steps = newJArray()
  for s in p.steps: steps.add(stepToJson(s))
  j["steps"] = steps
  let dir = parentDir(path)
  if dir.len > 0 and dir != ".":
    createDir(dir)
  writeFile(path, $j)
  writeFile(path & ".cursor", $p.cursor)

proc planToJson*(p: Plan): JsonNode =
  ## Full plan as JSON (id, goal, cursor, status, timestamp, steps) — used by
  ## the session to record a `plan` node in the history (RFC 1000).
  result = newJObject()
  result["id"] = %p.id
  result["goal"] = %p.goal
  result["cursor"] = %p.cursor
  result["status"] = %($p.status)
  result["timestamp"] = %p.timestamp
  var steps = newJArray()
  for s in p.steps: steps.add(stepToJson(s))
  result["steps"] = steps

proc jstr(j: JsonNode, key: string): string =
  ## String field accessor that returns "" when absent.
  if key in j and j[key].kind == JString: j[key].str else: ""

proc stepFromJson(j: JsonNode): Step =
  result = Step(
    kind: parseEnum[StepKind](
      if "kind" in j and j["kind"].kind == JString: j["kind"].str else: "skGenerate"),
    name: jstr(j, "name"),
    source: jstr(j, "source"),
    filter: jstr(j, "filter"),
    forWhom: jstr(j, "for"),
    input: jstr(j, "input"),
    length: jstr(j, "length"),
    skill: jstr(j, "skill"),
    context: jstr(j, "context"),
    path: jstr(j, "path"),
    content: jstr(j, "content"),
    items: jstr(j, "items"),
    title: jstr(j, "title"),
    status: parseEnum[StepStatus](
      if "status" in j and j["status"].kind == JString: j["status"].str else: "ssPending"),
    output: jstr(j, "output"),
  )

proc loadPlan*(path: string): Plan =
  ## Loads a saved plan (including its cursor from path & ".cursor" if present).
  let j = parseJson(readFile(path))
  result = Plan(
    id: jstr(j, "id"),
    goal: jstr(j, "goal"),
    cursor: (if "cursor" in j: j["cursor"].getInt() else: 0),
    status: parseEnum[PlanStatus](
      if "status" in j and j["status"].kind == JString: j["status"].str else: "psPaused"),
    timestamp: jstr(j, "timestamp"),
    steps: @[])
  if "steps" in j and j["steps"].kind == JArray:
    for s in j["steps"]:
      result.steps.add(stepFromJson(s))
  # resume point: prefer the sidecar cursor file if present
  if fileExists(path & ".cursor"):
    try:
      result.cursor = parseInt(readFile(path & ".cursor").strip())
    except ValueError:
      discard