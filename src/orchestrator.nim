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

import std/[strutils]
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