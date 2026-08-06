## Model Evals - Black-box model probes (RFC 9700)
##
## Tests the MODEL's behavior, not our code.
## Unlike unit tests (deterministic, offline), model evals are probabilistic
## and require the real model + backend.

import std/[os, strutils]
import ./orchestrator, ./harness

type
  EvalResult* = object
    name*: string
    rate*: float
    trials*: int
    success*: int
    fail*: int

  ## A rubric is the band-aid: it turns a chaotic model reply into a 0..1
  ## score, given the system instructions + user message it was produced from.
  ## The scorer itself is deterministic code (unit-testable); the model is just
  ## its input. "Scoring state_bake" = bake(system+user) -> generate -> score.
  Rubric* = object
    name*: string
    required*: seq[string]   # substrings the reply MUST contain
    forbidden*: seq[string]  # substrings that must NOT appear
    minLen*: int             # minimum reply length (0 = no constraint)
    maxLen*: int             # maximum reply length (0 = no constraint)
    expectToolCall*: bool    # reply must contain a [tool] call

proc scoreReply*(reply: string, r: Rubric): float =
  ## Deterministic rubric score in [0,1]. 1.0 = reply satisfies every
  ## constraint. This is the *program* side: fully unit-testable offline.
  var total = 0
  var hits = 0
  for req in r.required:
    inc total
    if reply.contains(req): inc hits
  for f in r.forbidden:
    inc total
    if not reply.contains(f): inc hits
  if r.minLen > 0:
    inc total
    if reply.len >= r.minLen: inc hits
  if r.maxLen > 0:
    inc total
    if reply.len <= r.maxLen: inc hits
  if r.expectToolCall:
    inc total
    if parseToolCalls(reply).len > 0: inc hits
  result = if total == 0: 1.0 else: hits.float / total.float

proc passRate*(scores: openArray[float], threshold: float = 0.7): float =
  ## Fraction of trials whose score clears the threshold — the eval metric.
  ## "pass" means the reply landed inside the rubric's basin of attraction.
  var ok = 0
  for s in scores:
    if s >= threshold: inc ok
  result = if scores.len == 0: 0.0 else: ok.float / scores.len.float

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

when not defined(harnessOffline):
  import ./bootstrap, ./config, ./session_manager

  ## A "scoring state_bake" eval: bake (system+user) -> generate -> score.
  ## The MODEL is the chaotic input; the SCORER is deterministic code. These
  ## are evals (validate by eye/rate), NOT unit tests — the model output is
  ## non-reproducible in the rough, so we assert basins, not exact tokens.
  type ScoredScenario* = object
    name*: string
    userMsg*: string
    rubric*: Rubric
    trials*: int

  const ScoredScenarios* = @[
    ScoredScenario(
      name: "tool-call on write request",
      userMsg: "write a poem about roses",
      rubric: Rubric(name: "toolcall", expectToolCall: true,
                     required: @["run_pipeline"], minLen: 4),
      trials: 3),
    ScoredScenario(
      name: "meeting intro anchors",
      userMsg: "hi my name is Alice",
      rubric: Rubric(name: "intro", required: @["Alice"], minLen: 1),
      trials: 3),
    ScoredScenario(
      name: "bake-examples teach turn format",
      userMsg: "hello there",
      # The system prompt baked into state carries `User: hi / Bot: Hello!`
      # examples. If the bake works, the model answers AS the bot (no "User:"
      # echo, non-empty, no trailing "Bot:" prompt continuation).
      rubric: Rubric(name: "bake-examples", forbidden: @["User:"],
                     minLen: 1),
      trials: 3),
  ]

  proc runScoredEval*(cfg: NimoConfig, trials: int = 3,
                      cwd: string = getCurrentDir()): EvalResult =
    ## Boots the real model, bakes system+user, generates, scores. Returns the
    ## total pass rate across all scenarios — the eval metric (basin check).
    var totalTrials = 0
    for env in ScoredScenarios:
      totalTrials += trials
    result = EvalResult(name: "scoring_state_bake", trials: totalTrials)
    let bs = bootstrapSession(cfg, cwd)
    if not bs.ok:
      echo "[model-eval] bootstrap failed:"
      for l in bs.lines: echo "  " & l
      return result
    var s = bs.session
    for env in ScoredScenarios:
      var scoredScores: seq[float]
      for t in 0 ..< trials:
        # Each trial re-generates over the SAME baked state (deterministic
        # initial condition + fixed seed at initModel), then scores the reply
        # against the rubric's basin of attraction.
        var r = s.generateTurn(env.userMsg, nil, DefaultTemp, DefaultTopP, cfg.maxTokens)
        scoredScores.add(scoreReply(r, env.rubric))
      let rate = passRate(scoredScores, 0.7)
      echo "  " & env.name & ": " & rate.formatFloat(ffDecimal, 1) &
           " ($1/$2)" % [$int(rate * trials.float), $trials]
      result.success += int(rate * trials.float)
    result.rate = if result.trials > 0: result.success.float / result.trials.float else: 0.0
    return result



proc main() =
  let args = commandLineParams()
  if args.len == 0:
    echo """nimo model-eval — Black-box model probes

Two families:
  * planner compilation (offline, deterministic) — the default
  * scored state_bake   (online, real model) — bake system+user -> generate
    -> score against a rubric; reports the pass rate (basin-of-attraction).
    EVALS are validated by eye/rate, NOT exact-match unit tests — the model
    is chaotic, so we never assert exact tokens.

Usage:
  nimo model-eval                    # planner evals (default 5 trials)
  nimo model-eval --trials 10        # set trial count
  nimo model-eval --scored           # real-model rubric-scored evals
  nimo model-eval --scored --seed 42 # fixed seed (reproducible initial cond)
"""
    quit(0)

  var trials = 5
  var scored = false
  var seed: int64 = -1
  for i, a in args:
    if a == "--trials" and i + 1 < args.len:
      try: trials = parseInt(args[i + 1])
      except ValueError: echo "Error: invalid --trials value"; quit(1)
    elif a == "--scored":
      scored = true
    elif a == "--seed" and i + 1 < args.len:
      try: seed = parseInt(args[i + 1])
      except ValueError: echo "Error: invalid --seed value"; quit(1)

  when not defined(harnessOffline):
    if scored:
      var cfg = loadConfig()
      if seed >= 0: cfg.seed = seed
      let r = runScoredEval(cfg, trials)
      echo "[model-eval] scored state_bake: $1% ($2/$3)" % [
        (r.rate * 100).formatFloat(ffDecimal, 0), $r.success, $r.trials]
      quit(0)

  discard runEval(trials)

when isMainModule:
  main()
