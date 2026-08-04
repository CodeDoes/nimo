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
  # Pattern continuation: does the model continue a repeating pattern?
  PatternPrompt* = "1, 2, 3, 4, 5, "
  
  # State retention: does the model remember context from earlier in generation?
  StatePrompt* = "The quick brown fox jumped over the lazy dog. Now tell me what animal was lazy: "
  
  # Planner emission: can the model emit parseable plan structure?
  PlannerPrompt* = "Create a plan for writing a story about a lighthouse. Output your plan as [step] lines."
  
  # Natural response: does the model respond naturally to simple prompts?
  NaturalPrompt* = "Say hello in exactly 3 words."
  
  # Multi-turn coherence: can the model maintain coherence across turns?
  CoherencePrompt* = "Once upon a time there was a lighthouse keeper. The keeper was lonely."

proc runPatternEval*(session: var Session, generate: GenerateFn, trials: int): EvalResult =
  ## Tests: can the model continue a numerical pattern?
  result = EvalResult(name: "pattern_continuation", trials: trials)
  for i in 1 .. trials:
    let reply = session.generateTurn(PatternPrompt, bs.generate, DefaultTemp, DefaultTopP, 10)
    if reply.len > 0 and ("6" in reply or "six" in reply.toLowerAscii()):
      inc result.success
    else:
      inc result.fail
  result.rate = if result.success + result.fail > 0: result.success.float / (result.success + result.fail).float else: 0.0

proc runStateEval*(session: var Session, generate: GenerateFn, trials: int): EvalResult =
  ## Tests: does the model retain state from earlier context?
  result = EvalResult(name: "state_retention", trials: trials)
  for i in 1 .. trials:
    let reply = cfg.session.generateTurn(StatePrompt, cfg.generate, DefaultTemp, DefaultTopP, 20)
    if "dog" in reply.toLowerAscii() or "lazy" in reply.toLowerAscii():
      inc result.success
    else:
      inc result.fail
  result.rate = if result.success + result.fail > 0: result.success.float / (result.success + result.fail).float else: 0.0

proc runPlannerEval*(session: var Session, generate: GenerateFn, trials: int): EvalResult =
  ## Tests: can the model emit parseable plan structure?
  result = EvalResult(name: "planner_emission", trials: trials)
  for i in 1 .. trials:
    let reply = cfg.session.generateTurn(PlannerPrompt, cfg.generate, DefaultTemp, DefaultTopP, 100)
    # Check for [step] or structured output
    if reply.contains("[step]") or reply.contains("step") and reply.contains("{"):
      inc result.success
    else:
      inc result.fail
  result.rate = if result.success + result.fail > 0: result.success.float / (result.success + result.fail).float else: 0.0

proc runNaturalEval*(session: var Session, generate: GenerateFn, trials: int): EvalResult =
  ## Tests: does the model respond naturally?
  result = EvalResult(name: "natural_response", trials: trials)
  for i in 1 .. trials:
    let reply = cfg.session.generateTurn(NaturalPrompt, cfg.generate, DefaultTemp, DefaultTopP, 15)
    # Should be short and contain hello/greeting
    if reply.len > 0 and reply.len < 50 and ("hello" in reply.toLowerAscii() or "hi" in reply.toLowerAscii()):
      inc result.success
    else:
      inc result.fail
  result.rate = if result.success + result.fail > 0: result.success.float / (result.success + result.fail).float else: 0.0

proc runEval*(bs: BootstrapResult): int =
  ## Runs all model evals and reports rates.
  echo "[model-eval] Running $1 trials per eval" % [$trials]
  echo ""
  
  echo "[model-eval] Pattern continuation (expect '6' or 'six'):"
  let pattern = runPatternEval(bs.session, bs.generate, trials)
  echo "  rate=$1% ($2/$3)" % [$pattern.rate.formatFloat(ffDecimal, 0), $pattern.success, $pattern.trials]
  
  echo "[model-eval] State retention (expect 'dog' or 'lazy'):"
  let state = runStateEval(bs.session, bs.generate, trials)
  echo "  rate=$1% ($2/$3)" % [$state.rate.formatFloat(ffDecimal, 0), $state.success, $state.trials]
  
  echo "[model-eval] Planner emission (expect structured output):"
  let planner = runPlannerEval(bs.session, bs.generate, trials)
  echo "  rate=$1% ($2/$3)" % [$planner.rate.formatFloat(ffDecimal, 0), $planner.success, $planner.trials]
  
  echo "[model-eval] Natural response (expect short greeting):"
  let natural = runNaturalEval(bs.session, bs.generate, trials)
  echo "  rate=$1% ($2/$3)" % [$natural.rate.formatFloat(ffDecimal, 0), $natural.success, $natural.trials]
  
  echo ""
  echo "[model-eval] Summary:"
  let total = pattern.success + state.success + planner.success + natural.success
  let totalTrials = pattern.trials + state.trials + planner.trials + natural.trials
  let overall = if totalTrials > 0: total.float / totalTrials.float else: 0.0
  echo "  overall: $1% ($2/$3)" % [overall.formatFloat(ffDecimal, 0), $total, $totalTrials]
  
  return 0

proc main() =
  let args = commandLineParams()
  if args.len == 0:
    echo """nimo model-eval — Black-box model probes

Runs fixed prompts through the model and reports success rates.
Unlike unit tests, these probe the MODEL's behavior.

Usage:
  nimo model-eval                    # Run all evals (5 trials)
  nimo model-eval --trials 10        # Set number of trials
"""
    quit(0)
  
  var trials = 5
  for i, a in args:
    if a == "--trials" and i + 1 < args.len:
      try: trials = parseInt(args[i + 1])
      except: echo "Error: invalid --trials value"; quit(1)
  
  var cfg = loadConfig()
  let bs = bootstrapSession(cfg, getCurrentDir())
  for line in bs.lines: echo line
  if not bs.ok: quit(1)
  
  discard runEval(bs)

when isMainModule:
  main()
