## Model Evals - Black-box model probes (RFC 9700)
##
## Tests the MODEL's behavior, not our code.
## Unlike unit tests (deterministic, offline), model evals are probabilistic
## and require the real model + backend.

import std/[os, strutils, sequtils]
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

  ConstraintDiagnostic* = object
    ## One rigid check within a rubric, plus a WHY: what was expected and what
    ## was actually observed in this reply. This is what lets an eval diagnose
    ## WHERE the model degraded, not just that it scored lower.
    label*: string
    passed*: bool
    why*: string
    weight*: float

  ScoredReply* = object
    overall*: float          # continuous 0..1 mean of the diagnostics
    diagnostics*: seq[ConstraintDiagnostic]

proc trimReply*(r: string, n: int = 90): string =
  ## Short display form of a reply for diagnostics (keeps "why" self-contained
  ## without dumping whole responses into the log).
  let s = r.replace("\n", " ")
  result = if s.len > n: s[0 ..< n] & "…" else: s

proc buildDiagnostics*(reply: string, r: Rubric): seq[ConstraintDiagnostic] =
  ## Turn a rubric into concrete per-part checks with explanations. The label
  ## explains WHAT is checked; `why` explains WHY it passed/failed (observed
  ## evidence, e.g. the offending substring or a short quote). This is the
  ## deterministic, unit-testable program side.
  let t = strip(reply)
  for req in r.required:
    let ok = reply.contains(req)
    result.add(ConstraintDiagnostic(
      label: "reply contains \"" & req & "\"",
      passed: ok,
      why: if ok: "found '" & req & "' in reply"
           else: "NOT found — reply: \"" & t & "\"",
      weight: 1.0))
  for f in r.forbidden:
    let ok = not reply.contains(f)
    result.add(ConstraintDiagnostic(
      label: "reply avoids forbidden \"" & f & "\"",
      passed: ok,
      why: if ok: "never appears in reply"
           else: "shows up — reply: \"" & t & "\"",
      weight: 1.0))
  if r.minLen > 0:
    let ok = reply.len >= r.minLen
    result.add(ConstraintDiagnostic(
      label: "reply length >= " & $r.minLen,
      passed: ok,
      why: "len=" & $reply.len & (if ok: " so >= " & $r.minLen else: " — too short to be a real answer"),
      weight: 1.0))
  if r.maxLen > 0:
    let ok = reply.len <= r.maxLen
    result.add(ConstraintDiagnostic(
      label: "reply length <= " & $r.maxLen,
      passed: ok,
      why: "len=" & $reply.len & (if ok: " so <= " & $r.maxLen else: " — overlong, may be looping"),
      weight: 1.0))
  if r.expectToolCall:
    let n = parseToolCalls(reply).len
    let ok = n > 0
    result.add(ConstraintDiagnostic(
      label: "reply emits a [tool] call",
      passed: ok,
      why: if ok: "found " & $n & " parseable [tool] call(s)"
           else: "no [tool] call parsed — reply: \"" & t & "\"",
      weight: 1.0))

proc scoreDetailed*(reply: string, r: Rubric): ScoredReply =
  ## Detailed scoring: overall 0..1 plus per-part diagnostics (label + why).
  result.diagnostics = buildDiagnostics(reply, r)
  if result.diagnostics.len == 0:
    result.overall = 1.0
    return
  var weighted = 0.0
  var hits = 0.0
  for d in result.diagnostics:
    weighted += d.weight
    if d.passed: hits += d.weight
  result.overall = hits / weighted

proc scoreReply*(reply: string, r: Rubric): float =
  ## Continuous 0..1 score = mean of the per-part diagnostics (kept for
  ## backward-compat with the eval loop + unit tests).
  result = scoreDetailed(reply, r).overall

proc passRate*(scores: openArray[float], threshold: float = 0.7): float =
  ## Fraction of trials whose score clears the threshold. Useful for a quick
  ## boolean view, but the SCORED eval reports the continuous mean instead —
  ## a threshold hides 90%->70% drift that a mean exposes.
  var ok = 0
  for s in scores:
    if s >= threshold: inc ok
  result = if scores.len == 0: 0.0 else: ok.float / scores.len.float

proc meanScore*(scores: openArray[float]): float =
  ## Continuous mean of per-trial rubric scores in [0,1] — the degradation-
  ## sensitive metric. 1.0 = every trial satisfied every constraint.
  if scores.len == 0: return 0.0
  var sum = 0.0
  for s in scores: sum += s
  result = sum / scores.len.float

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
  import std/[json, times]
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

  type ScenarioDiag* = object   # one rubric part, aggregated over trials
    label*: string      # WHAT is checked
    rate*: float        # fraction of trials where this part passed
    why*: string        # observed evidence from the FIRST failing trial

  type ScenarioRun* = object   # one scenario's continuous score
    name*: string
    avg*: float       # mean of per-trial scores in [0,1]
    scores*: seq[float]  # every trial's score, so spread is visible
    diag*: seq[ScenarioDiag]  # per-part breakdown, degradation diagnosis

  type ScoredRun* = object
    timestamp*: string
    model*: string
    seed*: int64
    trials*: int
    scenarios*: seq[ScenarioRun]
    overall*: float     # mean across all scenario trials

  proc toJson(r: ScoredRun): JsonNode =
    var j = newJObject()
    j["type"] = %"scored_eval"
    j["timestamp"] = %r.timestamp
    j["model"] = %r.model
    j["seed"] = %r.seed
    j["trials"] = %r.trials
    j["overall"] = %r.overall
    var scs = newJArray()
    for s in r.scenarios:
      var o = newJObject()
      o["name"] = %s.name
      o["avg"] = %s.avg
      var scores = newJArray()
      for x in s.scores: scores.add(%x)
      o["scores"] = scores
      var diags = newJArray()
      for d in s.diag:
        var dj = newJObject()
        dj["label"] = %d.label
        dj["rate"] = %d.rate
        dj["why"] = %d.why
        diags.add(dj)
      o["diag"] = diags
      scs.add(o)
    j["scenarios"] = scs
    result = j

  proc loadScoredRun*(path: string): ScoredRun =
    ## Loads a saved scored run (used as a baseline for degradation detection).
    if not fileExists(path): return ScoredRun()
    try:
      let j = parseJson(readFile(path))
      if j.kind != JObject: return ScoredRun()
      result.timestamp = if j.hasKey("timestamp"): j["timestamp"].getStr("") else: ""
      result.model = if j.hasKey("model"): j["model"].getStr("") else: ""
      result.seed = if j.hasKey("seed"): j["seed"].getInt() else: 0
      result.trials = if j.hasKey("trials"): j["trials"].getInt() else: 0
      result.overall = if j.hasKey("overall"): j["overall"].getFloat() else: 0.0
      if j.hasKey("scenarios") and j["scenarios"].kind == JArray:
        for o in j["scenarios"]:
          if o.kind != JObject: continue
          var s = ScenarioRun(
            name: (if o.hasKey("name"): o["name"].getStr("") else: ""),
            avg: (if o.hasKey("avg"): o["avg"].getFloat() else: 0.0))
          if o.hasKey("scores") and o["scores"].kind == JArray:
            for x in o["scores"]:
              if x.kind == JFloat or x.kind == JInt:
                s.scores.add(x.getFloat())
          if o.hasKey("diag") and o["diag"].kind == JArray:
            for d in o["diag"]:
              if d.kind != JObject: continue
              s.diag.add(ScenarioDiag(
                label: (if d.hasKey("label"): d["label"].getStr("") else: ""),
                rate: (if d.hasKey("rate"): d["rate"].getFloat() else: 0.0),
                why: (if d.hasKey("why"): d["why"].getStr("") else: "")))
          result.scenarios.add(s)
    except CatchableError:
      return ScoredRun()

  proc runScoredEval*(cfg: NimoConfig, trials: int = 3,
                      cwd: string = getCurrentDir()): ScoredRun =
    ## Boots the real model, bakes system+user, generates one reply per trial,
    ## scores each against the rubric, and returns the CONTINUOUS per-scenario
    ## means + overall. No pass/fail: the numbers themselves reveal drift.
    result.timestamp = nowStr()
    result.model = cfg.modelPath
    result.seed = cfg.seed
    var allScores: seq[float]
    let bs = bootstrapSession(cfg, cwd)
    if not bs.ok:
      echo "[model-eval] bootstrap failed:"
      for l in bs.lines: echo "  " & l
      return result
    var s = bs.session
    for env in ScoredScenarios:
      var trialScores: seq[float]
      var trialDiags: seq[ScoredReply]   # detailed, for per-part aggregation
      let n = if env.trials > 0: env.trials else: trials
      for t in 0 ..< n:
        var r = s.generateTurn(env.userMsg, nil, DefaultTemp, DefaultTopP, cfg.maxTokens)
        let sd = scoreDetailed(r, env.rubric)
        trialScores.add(sd.overall)
        trialDiags.add(sd)
      # Aggregate each rubric part across trials; attach the first failing why.
      var diag: seq[ScenarioDiag]
      if trialDiags.len > 0:
        for ci in 0 ..< trialDiags[0].diagnostics.len:
          var passes = 0
          var firstWhy = ""
          for td in trialDiags:
            if ci < td.diagnostics.len and td.diagnostics[ci].passed:
              inc passes
            elif ci < td.diagnostics.len:
              if firstWhy.len == 0: firstWhy = td.diagnostics[ci].why
          diag.add(ScenarioDiag(
            label: trialDiags[0].diagnostics[ci].label,
            rate: passes.float / n.float,
            why: firstWhy))
      result.scenarios.add(ScenarioRun(name: env.name, avg: meanScore(trialScores),
                                       scores: trialScores, diag: diag))
      allScores.add(trialScores)
    result.trials = allScores.len
    result.overall = meanScore(allScores)



proc main() =
  let args = commandLineParams()
  if args.len == 0:
    echo """nimo model-eval — Black-box model probes

Two families:
  * planner compilation (offline, deterministic) — the default
  * scored state_bake   (online, real model) — bake system+user -> generate
    -> score against a rubric; reports CONTINUOUS per-scenario means + overall
    percent. No pass/fail: numbers alone surface degradation. EVALS are
    validated by eye/delta, NOT exact-match unit tests — the model is chaotic.

Usage:
  nimo model-eval                    # planner evals (default 5 trials)
  nimo model-eval --trials 10        # set trial count
  nimo model-eval --scored           # real-model rubric-scored evals
  nimo model-eval --scored --seed 42 # fixed seed (reproducible initial cond)
  nimo model-eval --scored --save results.json
  nimo model-eval --scored --baseline results.json   # delta + DEGRADED flag
"""
    quit(0)

  var trials = 5
  var scored = false
  var seed: int64 = -1
  var baseline = ""
  var saveTo = ""
  for i, a in args:
    if a == "--trials" and i + 1 < args.len:
      try: trials = parseInt(args[i + 1])
      except ValueError: echo "Error: invalid --trials value"; quit(1)
    elif a == "--scored":
      scored = true
    elif a == "--seed" and i + 1 < args.len:
      try: seed = parseInt(args[i + 1])
      except ValueError: echo "Error: invalid --seed value"; quit(1)
    elif a == "--baseline" and i + 1 < args.len:
      baseline = args[i + 1]
    elif a == "--save" and i + 1 < args.len:
      saveTo = args[i + 1]

  when not defined(harnessOffline):
    if scored:
      var cfg = loadConfig()
      if seed >= 0: cfg.seed = seed
      let r = runScoredEval(cfg, trials)
      echo "[model-eval] scored state_bake  (" & r.timestamp & ")"
      echo "  model=" & r.model & "  seed=" & $r.seed
      for s in r.scenarios:
        echo "  " & s.name & ": " & (s.avg * 100).formatFloat(ffDecimal, 1) &
             "%  (" & $s.scores.len & " trials)"
        for d in s.diag:
          echo "      · " & d.label & ": " & (d.rate * 100).formatFloat(ffDecimal, 0) &
               "%" & (if d.why.len > 0: "  — " & d.why else: "")
      echo "  overall: " & (r.overall * 100).formatFloat(ffDecimal, 1) & "%"

      # Optional baseline: diff this run against a saved one to surface
      # degradation (continuous delta, no pass/fail gate).
      if baseline.len > 0:
        let b = loadScoredRun(baseline)
        if b.scenarios.len == 0:
          echo "  [baseline] no data in " & baseline
        else:
          echo "  [baseline] diff vs " & baseline & " (" & b.timestamp & ")"
          for s in r.scenarios:
            var delta = 0.0
            var found = false
            for bs in b.scenarios:
              if bs.name == s.name:
                delta = s.avg - bs.avg
                found = true
                break
            if not found:
              echo "  " & s.name & ": " & (s.avg * 100).formatFloat(ffDecimal, 1) & "% (new)"
            else:
              let d = delta * 100
              let mark = if d < -5.0: " DEGRADED" elif d > 5.0: " improved" else: ""
              echo "  " & s.name & ": " & (s.avg * 100).formatFloat(ffDecimal, 1) &
                   "% (delta " & d.formatFloat(ffDecimal, 1) & "pp)" & mark
          let od = (r.overall - b.overall) * 100
          echo "  overall: " & (r.overall * 100).formatFloat(ffDecimal, 1) &
               "% (delta " & od.formatFloat(ffDecimal, 1) & "pp)" &
               (if od < -5.0: " DEGRADED" else: "")

      if saveTo.len > 0:
        writeFile(saveTo, $toJson(r))
        echo "  [saved] " & saveTo
      quit(0)

  discard runEval(trials)

when isMainModule:
  main()
