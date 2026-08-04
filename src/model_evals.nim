## Model Evals - Black-box model probes (RFC 9700)
##
## Tests the MODEL's behavior, not our code.
## Unlike unit tests (deterministic, offline), model evals are probabilistic
## and require the real model + backend.
##
## Concept: run fixed prompts, measure rates over N trials.
## The planner is the distillation target: it ships only when its emission
## rate clears the bar.

import std/[os, strutils, times, json]
import ./config, ./bootstrap, ./session_manager, ./orchestrator

type
  EvalResult* = object
    name*: string
    rate*: float      # success rate (0.0 to 1.0)
    trials*: int
    success*: int
    fail*: int

const
  FixedPrompts* = @[
    ("planner", "write a story about a lighthouse"),
    ("planner", "remember that the sky is blue"),
    ("planner", "summarize the history of Rome"),
    ("planner", "create a poem about roses"),
    ("planner", "what is the capital of France?")
  ]

proc runEval*(cfg: NimoConfig, cwd: string = ".", trials: int = 10): int =
  ## Runs model evals and reports rates.
  echo "[model-eval] Running $1 trials per prompt" % [$trials]
  echo ""
  
  var results: seq[EvalResult] = @[]
  
  for (category, prompt) in FixedPrompts:
    echo "[model-eval] Testing: $1" % [prompt]
    
    var success = 0
    var fail = 0
    
    for i in 1 .. trials:
      # Compile plan from prompt
      let plan = interpret(prompt)
      
      # Check: plan has at least one step
      if plan.steps.len > 0:
        inc success
      else:
        inc fail
    
    let rate = if success + fail > 0: success.float / (success + fail).float else: 0.0
    echo "  rate=$1 ($2/$3 successful)" % [$rate.formatFloat(ffDecimal, 2), $success, $trials]
    
    results.add(EvalResult(
      name: prompt,
      rate: rate,
      trials: trials,
      success: success,
      fail: fail
    ))
  
  echo ""
  echo "[model-eval] Summary:"
  for r in results:
    echo "  $1: $2" % [r.name[0 .. min(40, r.name.len - 1)], "$1%".format(r.rate * 100.0)]
  
  return 0

proc main() =
  let args = commandLineParams()
  if args.len == 0:
    echo """nimo model-eval — Black-box model probes

Runs fixed prompts through the model and reports success rates.
Unlike unit tests, these probe the MODEL's behavior.

Usage:
  nimo model-eval                    # Run with defaults (10 trials)
  nimo model-eval --trials 20        # Set number of trials
"""
    quit(0)
  
  var trials = 10
  for i, a in args:
    if a == "--trials" and i + 1 < args.len:
      try: trials = parseInt(args[i + 1])
      except: echo "Error: invalid --trials value"; quit(1)
  
  var cfg = loadConfig()
  let bs = bootstrapSession(cfg, getCurrentDir())
  for line in bs.lines: echo line
  if not bs.ok: quit(1)
  
  discard runEval(cfg, getCurrentDir(), trials)

when isMainModule:
  main()
