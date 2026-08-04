## orchestrator.nim — goal -> plan (RFC 3400)
## THE seam between natural language and the plan/engine runtime.
##
## Developer journey: a user message enters here (`interpret`). A template
## (below) builds a Plan of pointed Steps; the engine runs it. To change what a
## goal DOES, edit the template for that intent — you do NOT need to read the
## whole codebase to change one behaviour.
##
## The learned planner (RFC 8000/3500, Phase 5 distillation) swaps in BEHIND
## this same `interpret` seam: the keyword registry is the deterministic
## placeholder, so the system works before any skill bake exists.
##
## Deterministic + offline (no model import): fully covered by `nimo unit`.

import std/[strutils, json]
import ./program

type Intent* = enum
  itAnswer   ## answer a question / anything not matched
  itStory    ## write a story / tale / narrative
  itPoem     ## write a poem
  itChapter  ## write / improve a chapter
  itMemory   ## remember / note something

proc matchIntent*(goal: string): Intent =
  ## Chooses an intent from the natural-language goal by keyword.
  let g = goal.toLowerAscii()
  if g.contains("poem"):
    itPoem
  elif g.contains("chapter"):
    itChapter
  elif g.contains("remember") or g.contains("note that"):
    itMemory
  elif g.contains("story") or g.contains("tale") or g.contains("narrative"):
    itStory
  else:
    itAnswer

proc buildPlan(intent: Intent, goal: string): Plan =
  result = newPlan(goal)
  case intent
  of itStory:
    result.addStep(extractStep("pull-context", "memory", "the story so far"))
    result.addStep(generateStep("draft-story", goal, "output:story"))
    result.addStep(writeStep("save-story", "story.md"))
    result.addStep(reportStep("story written"))
  of itPoem:
    result.addStep(generateStep("write-poem", goal, "output:poem"))
    result.addStep(writeStep("save-poem", "poem.md"))
    result.addStep(reportStep("poem written"))
  of itChapter:
    result.addStep(extractStep("pull-wiki", "wiki", "world + characters"))
    result.addStep(generateStep("draft-chapter", goal, "output:chapter"))
    result.addStep(validateStep("gate-quality", ""))
    result.addStep(writeStep("save-chapter", "chapter.md"))
    result.addStep(reportStep("chapter drafted"))
  of itMemory:
    result.addStep(extractStep("pull-relevant", "memory", goal))
    result.addStep(generateStep("note-it", goal, "output:note"))
    result.addStep(writeStep("save-note", "memory.md"))
    result.addStep(reportStep("noted"))
  of itAnswer:
    result.addStep(generateStep("answer", goal, "output:answer"))
    result.addStep(reportStep("done"))

proc interpret*(goal: string): Plan =
  ## The one entry point: a natural-language goal -> a compiled Plan.
  ## Swap the learned planner in here (Phase 5) without touching callers.
  return buildPlan(matchIntent(goal), goal)

# ---------------------------------------------------------------------------
# Planner-emission parsing (RFC 1100/3500)
# ---------------------------------------------------------------------------
# The learned planner emits a stream of step-emission lines; this compiles
# them into a Plan (the deterministic counterpart of `interpret`). Forms:
#   [step] generate {"skill": "output:story", "context": "..."}
#   [step] report  {"title": "done"}
#   {"step": "extract", "source": "memory", "filter": "..."}   (bare JSON)
# Non-emission prose lines are DROPPED: a plan must be pure structure.

proc stepFromName(name: string, j: JsonNode): Step =
  case name.toLowerAscii()
  of "extract":
    extractStep(if "name" in j: j["name"].getStr("extract") else: "extract",
                if "source" in j: j["source"].getStr("memory") else: "memory",
                if "filter" in j: j["filter"].getStr("") else: "",
                if "for" in j: j["for"].getStr("") else: "")
  of "generate":
    generateStep(if "name" in j: j["name"].getStr("generate") else: "generate",
                 if "context" in j: j["context"].getStr("") else: "",
                 if "skill" in j: j["skill"].getStr("") else: "")
  of "summarize":
    summarizeStep("summarize",
                  if "input" in j: j["input"].getStr("") else: "",
                  if "length" in j: j["length"].getStr("brief") else: "brief")
  of "validate":
    validateStep("validate",
                 if "text" in j: j["text"].getStr("") else: "")
  of "write":
    writeStep("write",
              if "path" in j: j["path"].getStr("") else: "",
              if "content" in j: j["content"].getStr("") else: "")
  of "loop":
    loopStep("loop",
             if "items" in j: j["items"].getStr("") else: "")
  of "report":
    reportStep(if "title" in j: j["title"].getStr("done") else: "done")
  else:
    # unknown emission line -> a plain generate step (safe, doesn't crash)
    generateStep("generate", $j)

proc compileEmission*(emission: string, goal: string): Plan =
  ## Parses planner step-emission text into a Plan. Returns a plan (possibly
  ## with zero steps) — it never throws on malformed lines.
  result = newPlan(goal)
  for line in emission.splitLines():
    let t = line.strip()
    if t.len == 0: continue
    var name = ""
    var argsJson = ""
    if t.startsWith("[step]") or t.startsWith("[tool]"):
      let rest = t[t.find(']') + 1 .. ^1].strip()
      let sp = rest.find({' ', '\t'})
      if sp > 0:
        name = rest[0 ..< sp]
        argsJson = rest[sp .. ^1].strip()
    elif t.startsWith("{"):
      # bare JSON object line
      try:
        let j = parseJson(t)
        if "step" in j: name = j["step"].getStr("")
        elif "name" in j: name = j["name"].getStr("")
        argsJson = $(if "arguments" in j: j["arguments"] else: j)
      except JsonParsingError:
        continue
    else:
      continue  # prose / non-emission line -> drop (plan must be structure)
    if name.len == 0: continue
    var j = newJObject()
    if argsJson.len > 0:
      try: j = parseJson(argsJson)
      except JsonParsingError: discard
    result.addStep(stepFromName(name, j))