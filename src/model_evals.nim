## Model Evals - Black-box model probes (RFC 9700)
##
## Tests the MODEL's behavior, not our code.
## Unlike unit tests (deterministic, offline), model evals are probabilistic
## and require the real model + backend.

import std/[os, strutils, sequtils, json, math]
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
    anyOf*: seq[string]      # at least ONE of these must appear (qualitative
                             # proxies: wander a warm-tone marker, a vivid
                             # word, etc.)
    minLen*: int             # minimum reply length (0 = no constraint)
    maxLen*: int             # maximum reply length (0 = no constraint)
    minSentences*: int       # min sentence-pacing beats (0 = no constraint)
    maxSentences*: int       # max sentence-pacing beats (0 = no constraint)
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

proc countSentences*(s: string): int =
  ## Rough sentence-count proxy. A 2.9B model won't reliably format, so we use
  ## sentence-terminating punctuation (not newlines) as pacing beats — used to
  ## spot curt/monotone vs rambling replies.
  for ch in s:
    if ch in {'.', '!', '?'}: inc result

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
  if r.anyOf.len > 0:
    # Qualitative proxy: at least ONE of a family of markers suffices, so we
    # don't over-fit to any single word. E.g. "friendly" = any warm marker.
    var hits: seq[string]
    for m in r.anyOf:
      if reply.contains(m): hits.add(m)
    let ok = hits.len > 0
    result.add(ConstraintDiagnostic(
      label: "at least one of {" & r.anyOf.join(", ") & "}",
      passed: ok,
      why: if ok: "found " & hits.join(", ")
           else: "none present — reply: \"" & t & "\"",
      weight: 1.0))
  let sentences = countSentences(reply)
  if r.minSentences > 0:
    let ok = sentences >= r.minSentences
    result.add(ConstraintDiagnostic(
      label: "pacing: >= " & $r.minSentences & " sentence(s)",
      passed: ok,
      why: "went " & $sentences & " pacing beat(s)" &
           (if ok: " so >= " & $r.minSentences else: " — curt, no substance"),
      weight: 1.0))
  if r.maxSentences > 0:
    let ok = sentences <= r.maxSentences
    result.add(ConstraintDiagnostic(
      label: "concision: <= " & $r.maxSentences & " sentence(s)",
      passed: ok,
      why: "came in " & $sentences & " sentence(s)" &
           (if ok: " so <= " & $r.maxSentences else: " — rambled past the limit"),
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

proc stddev*(xs: openArray[float]): float =
  ## Sample spread across trials/repeated asks — eval self-diagnosis.
  if xs.len < 2: return 0.0
  let m = meanScore(xs)
  var acc = 0.0
  for x in xs: acc += (x - m) * (x - m)
  result = sqrt(acc / (xs.len - 1).float)

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
  import std/[json, times, math, os]
  import ./bootstrap, ./config, ./session_manager, ./rwkv/state/cache

  # ---------------------------------------------------------------------------
  # Model-as-judge evals (RFC 9300): we do NOT hand-code rubrics that string-
  # match replies. The model itself is the expert. We bake a judge state that
  # knows how to score, then ask it to score an output on each metric, several
  # times per metric (the judge is chaotic too — repeated asks average out).
  #
  # Maintenance: adding a metric is adding ONE line of prose (name + what to
  # look for). No marker lists, no sentence counting, no thresholds.
  # ---------------------------------------------------------------------------

  var gLog: File
  var gLogOpen = false

  proc openJudgeLog() =
    ## Open the judge ask log so every generation and raw reply is captured.
    try:
      let p = getCurrentDir() / ".nimo"
      createDir(p)
      if open(gLog, p / "judge-asks.jsonl", fmWrite):
        gLogOpen = true
      else:
        gLogOpen = false
    except CatchableError:
      gLogOpen = false

  proc logAsk(scenario: string, rep: int, metric: string, genPrompt: string,
              sample: string, judgeRaw: string, score: float) =
    ## Log every judge ask fully — prompts, samples, raw replies, parsed score.
    if not gLogOpen: return
    let o = newJObject()
    o["when"] = %nowStr()
    o["scenario"] = %(scenario)
    o["rep"] = %(repr(rep))
    o["metric"] = %(metric)
    o["prompt"] = %(genPrompt)
    o["sample"] = %(sample)
    o["judge_raw"] = %(judgeRaw)
    o["score"] = %(repr(score))
    o["parsed"] = %(if score >= 0.0: "yes" else: "no")
    gLog.writeLine($o)

  const JudgeSystemPrompt* = """You are a judge. Your job is to evaluate samples against criteria.
Criteria: friendliness — the sample should be warm and kind
Sample: "I don't care."
Score: 1
Explanation: The sample is cold and dismissive, not warm or kind.

Example 2
Criteria: friendliness — the sample should be warm and kind
Sample: "I'm so sorry you're going through this. I'm here for you."
Score: 9
Explanation: The sample shows warmth and support, very friendly.

Example 3
Criteria: conciseness — the sample should be brief (1-2 sentences)
Sample: "The capital of France is Paris, which is located in north-central France and is known for its art, fashion, and the Eiffel Tower."
Score: 3
Explanation: The sample is too long and detailed, not concise.

Example 4
Criteria: conciseness — the sample should be brief (1-2 sentences)
Sample: "Paris."
Score: 8
Explanation: The sample is very brief, meets the conciseness criteria.

Now evaluate:

Criteria: {metric} — {ask}
Sample: {reply}
Score:
Explanation:
"""

  type ScoreMetric* = object
    name*: string        # metric label, e.g. "friendliness"
    ask*: string         # one line telling the judge what this metric means

  type JudgeScenario* = object
    name*: string
    generatePrompt*: string   # prompt that produces the sample output to judge
    focus*: string            # what trait the scenario probes (self-doc)
    metrics*: seq[ScoreMetric]
    trials*: int              # sample generations (1 keeps judge-repeat focus)
    preamble*: string         # optional chat-format turns establishing context

  const JudgeScenarios* = @[
    JudgeScenario(
      name: "friendly tone on a hard day",
      generatePrompt: "I had a rough day today.",
      focus: "empathy/tone",
      metrics: @[
        ScoreMetric(name: "friendliness",
                    ask: "warm, kind, emotionally supportive; not curt or dismissive"),
        ScoreMetric(name: "helpfulness",
                    ask: "offers genuine support or a next step, not platitudes"),
      ]),
    JudgeScenario(
      name: "followed a length instruction",
      generatePrompt: "Answer in at most two sentences. What is the capital of France?",
      focus: "instruction-following (form)",
      metrics: @[
        ScoreMetric(name: "instruction-following",
                    ask: "obeyed the stated form/length constraint precisely"),
        ScoreMetric(name: "accuracy",
                    ask: "factually correct and directly answers the question"),
      ]),
    JudgeScenario(
      name: "engaging prose has pacing",
      generatePrompt: "Tell me a short story about a fox crossing a river.",
      focus: "prose pacing (narrative beats)",
      metrics: @[
        ScoreMetric(name: "pacing",
                    ask: "good rhythm, varied sentence structure, not monotone"),
        ScoreMetric(name: "engagement",
                    ask: "holds interest, has narrative momentum"),
      ]),
    JudgeScenario(
      name: "vivid description engages senses",
      generatePrompt: "Describe a storm over the sea in a few sentences.",
      focus: "prose concreteness (sensory detail)",
      metrics: @[
        ScoreMetric(name: "vividness",
                    ask: "concrete sensory detail, shows rather than tells"),
        ScoreMetric(name: "imagery",
                    ask: "evocative, memorable language"),
      ]),
    # Cross-turn coherence: state_bake's real point. Bakes an establishing context
    # (preamble turns) then asks the model to answer a question that depends on
    # facts established in those earlier turns. The judge scores whether the
    # reply is consistent with the prior conversation.
    JudgeScenario(
      name: "cross-turn coherence (named context)",
      preamble: "\x00User: My name is Priya and I love astronomy.\n\nBot: Nice to meet you, Priya! Astronomy is a fascinating subject.\n\nUser: It's the stars and planets that interest me most.\n\nBot: The cosmos is amazing — you're in good company with your curiosity!",
      generatePrompt: "What is my name and what do I love?",
      focus: "context recall across turns (the point of state_bake)",
      metrics: @[ScoreMetric(
        name: "consistency",
        ask: "Does the sample honor facts established earlier in the conversation? If the user said their name is Priya and they love astronomy, the reply should reference these facts correctly. Ignoring, contradicting, or hallucinating new facts scores low."
      )]),
  ]

  type MetricScore* = object
    name*: string
    avg*: float            # mean of the judge's repeated scores, 0..10
    scores*: seq[float]    # every judge answer (0..10), spread visible
    unparsed*: int         # judge replies that weren't a number (self-diag)

  type ScenarioRun* = object
    name*: string
    focus*: string
    metrics*: seq[MetricScore]
    trials*: int           # sample generations judged

  type ScoredRun* = object
    timestamp*: string
    model*: string
    seed*: int64
    scenarios*: seq[ScenarioRun]
    overall*: float        # mean of all judge scores, 0..10

  proc toJson(r: ScoredRun): JsonNode =
    var j = newJObject()
    j["type"] = %"judge_eval"
    j["timestamp"] = %r.timestamp
    j["model"] = %r.model
    j["seed"] = %r.seed
    j["overall"] = %r.overall
    var scs = newJArray()
    for s in r.scenarios:
      var o = newJObject()
      o["name"] = %s.name
      o["focus"] = %s.focus
      var ms = newJArray()
      for m in s.metrics:
        var mj = newJObject()
        mj["name"] = %m.name
        mj["avg"] = %m.avg
        mj["unparsed"] = %m.unparsed
        var sc = newJArray()
        for x in m.scores: sc.add(%x)
        mj["scores"] = sc
        ms.add(mj)
      o["metrics"] = ms
      scs.add(o)
    j["scenarios"] = scs
    result = j

  proc loadScoredRun*(path: string): ScoredRun =
    ## Loads a saved judge eval (used as a baseline / for --trend).
    if not fileExists(path): return ScoredRun()
    try:
      let j = parseJson(readFile(path))
      if j.kind != JObject: return ScoredRun()
      result.timestamp = if j.hasKey("timestamp"): j["timestamp"].getStr("") else: ""
      result.model = if j.hasKey("model"): j["model"].getStr("") else: ""
      result.seed = if j.hasKey("seed"): j["seed"].getInt() else: 0
      result.overall = if j.hasKey("overall"): j["overall"].getFloat() else: 0.0
      if j.hasKey("scenarios") and j["scenarios"].kind == JArray:
        for o in j["scenarios"]:
          if o.kind != JObject: continue
          var s = ScenarioRun(
            name: (if o.hasKey("name"): o["name"].getStr("") else: ""),
            focus: (if o.hasKey("focus"): o["focus"].getStr("") else: ""))
          if o.hasKey("metrics") and o["metrics"].kind == JArray:
            for m in o["metrics"]:
              if m.kind != JObject: continue
              var mm = MetricScore(
                name: (if m.hasKey("name"): m["name"].getStr("") else: ""),
                avg: (if m.hasKey("avg"): m["avg"].getFloat() else: 0.0),
                unparsed: (if m.hasKey("unparsed"): m["unparsed"].getInt() else: 0))
              if m.hasKey("scores") and m["scores"].kind == JArray:
                for x in m["scores"]:
                  if x.kind == JFloat or x.kind == JInt:
                    mm.scores.add(x.getFloat())
              s.metrics.add(mm)
          result.scenarios.add(s)
    except CatchableError:
      return ScoredRun()

  proc deepCopyState(a: seq[float32]): seq[float32] =
    ## Generation mutates the RNN state in place; seq assignment aliases, so
    ## snapshots must be deep copies.
    result = newSeq[float32](a.len)
    for i in 0 ..< a.len: result[i] = a[i]

  proc parseScore*(reply: string): float =
    ## Pulls the first number out of the judge's reply (0..10). Returns -1 if
    ## the judge didn't produce a number — counted as `unparsed` (self-diag).
    var num = ""
    var seen = false
    for ch in reply:
      if ch in {'0'..'9', '.'}:
        num.add(ch)
        seen = true
      elif seen:
        break
    if not seen: return -1.0
    try:
      let v = parseFloat(num)
      result = if v > 10.0: 10.0 elif v < 0.0: 0.0 else: v
    except ValueError:
      result = -1.0

  proc bakeJudgeState(c: StateCache, s: Session, cfg: NimoConfig): seq[float32] =
    ## Second bake on the SAME loaded model: the judge's instruction set. Kept
    ## separate from the chat bake so scoring never bleeds into generation.
    result = c.bakeContext(s.model, s.tok, cfg.modelPath, cfg.vocabPath,
                           JudgeSystemPrompt)

  proc bakeChatState(c: StateCache, s: Session, cfg: NimoConfig,
                     context: string): seq[float32] =
    ## Bake an arbitrary chat-format context (a cross-turn preamble) into a
    ## state on the SAME loaded model, independent of the global chat bake.
    result = c.bakeContext(s.model, s.tok, cfg.modelPath, cfg.vocabPath, context)

  proc askJudge(s: var Session, judge: seq[float32], scenario: string,
                rep: int, generatePrompt: string, reply: string,
                metric: ScoreMetric): float =
    ## Present the sample to the judge, ask for a 0..10 score. No retry —
    ## every ask is fully logged so the raw judge reply is visible on failure.
    s.state = deepCopyState(judge)
    let ask = "You are judging an assistant's reply.\n" &
              "User prompt: " & generatePrompt & "\n" &
              "Assistant reply: " & reply & "\n" &
              "Score on " & metric.name & " (" & metric.ask & "):"
    let r = s.generateTurn(ask, nil, DefaultTemp, DefaultTopP, 14)
    let v = parseScore(r)
    logAsk(scenario, rep, metric.name, generatePrompt, reply, r, v)
    if v < 0.0:
      echo "[judge-fail] metric=" & metric.name & " scenario=" & scenario &
           " prompt=" & generatePrompt &
           " reply=\"" & reply.strip() & "\" judge_raw=\"" & r.strip() & "\""
    result = v

  proc runScoredEval*(cfg: NimoConfig, trials: int = 3,
                      cwd: string = getCurrentDir()): ScoredRun =
    ## 1) boot the real model with the CHAT bake; 2) snapshot it; 3) bake the
    ## JUDGE state on the same model; 4) per scenario, generate a sample once,
    ## then score it with the judge on every metric. Each generateTurn is a
    ## distinct draw, so `trials` samples give `trials` independent scores per
    ## metric without re-generating a fresh sample for every ask.
    result.timestamp = nowStr()
    result.model = cfg.modelPath
    result.seed = cfg.seed
    openJudgeLog()
    let bs = bootstrapSession(cfg, cwd)
    if not bs.ok:
      echo "[model-eval] bootstrap failed:"
      for l in bs.lines: echo "  " & l
      return result
    var s = bs.session
    let chat = deepCopyState(s.state)            # pristine chat bake
    let cache = initStateCache(cfg.stateCacheDir)
    let judge = bakeJudgeState(cache, s, cfg)
    var allMetrics: seq[float]
    let nSamples = max(1, trials)
    for sc in JudgeScenarios:
      var run = ScenarioRun(name: sc.name, focus: sc.focus)
      # per-metric collector (initialize one entry per metric)
      var mSlots: seq[MetricScore]
      for m in sc.metrics:
        mSlots.add(MetricScore(name: m.name))
      # cross-turn scenarios bake their own establishing context; otherwise use
      # the pristine chat bake so every scenario starts from the same baseline.
      let base = if sc.preamble.len > 0:
                   bakeChatState(cache, s, cfg, sc.preamble) else:
                   chat
      for rep in 0 ..< nSamples:
        s.state = deepCopyState(base)
        let sample = s.generateTurn(sc.generatePrompt, nil, DefaultTemp,
                                    DefaultTopP, cfg.maxTokens)
        logAsk(sc.name, rep, "__SAMPLE__", sc.generatePrompt, "", sample, -2.0)
        for mi, m in sc.metrics:
          let v = askJudge(s, judge, sc.name, rep, sc.generatePrompt, sample, m)
          if v < 0.0:
            inc mSlots[mi].unparsed
          else:
            mSlots[mi].scores.add(v)
      for mi, m in sc.metrics:
        let mm = mSlots[mi]
        mSlots[mi].avg =
          if mm.scores.len > 0: (sum(mm.scores) / mm.scores.len.float) else: 0.0
      run.metrics = mSlots
      run.trials = nSamples
      result.scenarios.add(run)
      for mSl in mSlots:
        allMetrics.add(mSl.avg)
    result.overall = if allMetrics.len > 0:
                       sum(allMetrics) / allMetrics.len.float else: 0.0
    close(gLog)

proc main() =
  let args = commandLineParams()
  if args.len == 0:
    echo "nimo model-eval — Black-box model probes"
    echo ""
    echo "Two families:"
    echo "  * planner compilation (offline, deterministic) — the default"
    echo "  * scored state_bake   (online, real model) — bake system+user -> generate"
    echo "    -> score against a rubric; reports CONTINUOUS per-scenario means + overall"
    echo "    percent. No pass/fail: numbers alone surface degradation. EVALS are"
    echo "    validated by eye/delta, NOT exact-match unit tests — the model is chaotic."
    echo ""
    echo "Usage:"
    echo "  nimo model-eval                    # planner evals (default 5 trials)"
    echo "  nimo model-eval --trials 10        # set repeat count per metric"
    echo "  nimo model-eval --scored           # model-as-judge scored evals (0-10)"
    echo "  nimo model-eval --scored --seed 42 # fixed seed (reproducible draws)"
    echo "  nimo model-eval --scored --save results.json"
    echo "  nimo model-eval --scored --baseline results.json   # delta + DEGRADED flag"
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
      echo "[model-eval] judge-scored state_bake  (" & r.timestamp & ")"
      echo "  model=" & r.model & "  seed=" & $r.seed
      echo "  scores are the MODEL's own 0-10 judgment (repeated asks, averaged)"
      for s in r.scenarios:
        echo "  " & s.name & "  (" & s.focus & ")"
        for m in s.metrics:
          let spread = if m.scores.len > 1:
            "  spread ±" & stddev(m.scores).formatFloat(ffDecimal, 1) else: ""
          echo "      · " & m.name & ": " & m.avg.formatFloat(ffDecimal, 1) &
               "/10  (" & $m.scores.len & " judge asks)" & spread &
               (if m.unparsed > 0: "  [" & $m.unparsed & " unparseable]" else: "")
      echo "  overall: " & r.overall.formatFloat(ffDecimal, 1) & "/10"

      # Auto-append to the eval history so degradation can be tracked over
      # time, not just against one hand-picked baseline file.
      let histDir = getCurrentDir() / ".nimo"
      let histFile = histDir / "model-evals.jsonl"
      try:
        createDir(histDir)
        let f = open(histFile, fmAppend)
        f.writeLine($toJson(r))
        f.close()
        echo "  [history] appended " & histFile
      except CatchableError:
        discard

      # Optional baseline: diff this run against a saved one to surface
      # degradation (continuous delta, no pass/fail gate).
      if baseline.len > 0:
        let b = loadScoredRun(baseline)
        if b.scenarios.len == 0:
          echo "  [baseline] no data in " & baseline
        else:
          echo "  [baseline] diff vs " & baseline & " (" & b.timestamp & ")"
          for s in r.scenarios:
            for m in s.metrics:
              var bm: MetricScore
              var found = false
              for bs in b.scenarios:
                if bs.name == s.name:
                  for mm in bs.metrics:
                    if mm.name == m.name:
                      bm = mm
                      found = true
                      break
                if found: break
              let d = (m.avg - bm.avg)
              let mark = if d < -0.5: " DEGRADED" elif d > 0.5: " improved" else: ""
              echo "  " & s.name & " / " & m.name & ": " &
                   m.avg.formatFloat(ffDecimal, 1) &
                   "/10 (delta " & d.formatFloat(ffDecimal, 1) & ")" & mark
          let od = r.overall - b.overall
          echo "  overall: " & r.overall.formatFloat(ffDecimal, 1) &
               "/10 (delta " & od.formatFloat(ffDecimal, 1) & ")" &
               (if od < -0.5: "  DEGRADED" else: "")

      if saveTo.len > 0:
        writeFile(saveTo, $toJson(r))
        echo "  [saved] " & saveTo
      quit(0)

  discard runEval(trials)

when isMainModule:
  main()
