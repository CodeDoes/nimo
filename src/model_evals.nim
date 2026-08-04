## Model Evals - Black-box model probes (RFC 9700)
##
## Tests the MODEL's behavior, not our code.
## Unlike unit tests (deterministic, offline), model evals are probabilistic
## and require the real model + backend.

import std/[os, strutils, times, json]
import ./config, ./bootstrap, ./session_manager, ./orchestrator

type
  EvalResult* = object
    name*: string
    rate*: float
    trials*: int
    success*: int
    fail*: int

const
  # Fixed prompts for planning evals
  PlannerPrompts* = @[
    "write a story about a lighthouse",
    "remember that the sky is blue",
    "create a poem about roses",
    "summarize the history of Rome",
    "what is the capital of France?"
  ]

proc runPlannerEval*(trials: int = 5): EvalResult =
  ## Tests: can the planner compile plans from natural language?
  result = EvalResult(name: "planner_compilation", trials: trials)
  for prompt in PlannerPrompts:
    for i in 1 .. (trials div PlannerPrompts.len + 1):
      let plan = interpret(prompt)
      if plan.steps.len > 0:
        inc result.success
      else:
        inc result.fail
  result.rate = if result.success + result.fail > 0: result.success.float / (result.success + result.fail).float else: 0.0

proc runEval*(trials: int = 5): int =
  ## Runs model evals and reports rates.
  echo "[model-eval] Running planner compilation evals ($1 trials)" % [$trials]
  echo ""
  
  let planner = runPlannerEval(trials)
  echo "  planner_compilation: $1% ($2/$3)" % [
    planner.rate.formatFloat(ffDecimal, 0),
    $planner.success,
    $planner.trials
  ]
  
  echo ""
  echo "[model-eval] Summary:"
  echo "  overall: $1%" % [planner.rate.formatFloat(ffDecimal, 0)]
  
  return 0

proc main() =
  let args = commandLineParams()
  if args.len == 0:
    echo """nimo model-eval — Black-box model probes

Runs fixed prompts and reports success rates.
Unlike unit tests, these probe the MODEL's behavior.

Usage:
  nimo model-eval                    # Run with defaults (5 trials)
  nimo model-eval --trials 10        # Set number of trials
"""
    quit(0)
  
  var trials = 5
  for i, a in args:
    if a == "--trials" and i + 1 < args.len:
      try: trials = parseInt(args[i + 1])
      except: echo "Error: invalid --trials value"; quit(1)
  
  discard runEval(trials)

when isMainModule:
  main()
