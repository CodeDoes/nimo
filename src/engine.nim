## engine.nim — the streaming executor (RFC 3600)
## run(plan, generate, sink, interrupt, maxSteps) — the ONE loop:
##   advance → execute step → checkpoint → next
##
## Composition-friendly: the engine is session-agnostic. It takes a `generate`
## callback (prompt -> text). Real use wires that to session.generateTurn /
## generateTurnStream; unit tests wire it to a scripted proc. So the engine is
## fully unit-testable offline, and the model is a pluggable detail.
##
## Streaming: every `sink` call is a chunk of produced text. Phase 1 turns that
## into per-token streaming by wiring the sink through generateTurnStream.

import std/[os]
import ./config, ./program, ./validate, ./memory

type
  InterruptCheck* = proc (): bool                 # nil = never interrupt
  # TokenSink / generation seams are defined in ./config so sessions and the
  # engine share one streaming contract without an import cycle.

  RunResult* = object
    stepsRun*: int
    completed*: bool       # plan reached the end
    aborted*: bool         # max-steps guard hit (plan never terminated)
    interrupted*: bool     # interrupt flag was set mid-run
    stoppedAt*: int        # cursor where it stopped (resume point)

proc emit(sink: TokenSink, text: string) =
  if sink != nil and text.len > 0:
    sink(text)

proc run*(p: var Plan, generate: GenerateFn = nil,
          sink: TokenSink = nil,
          interrupt: InterruptCheck = nil,
          maxSteps: int = 256,
          generateStream: GenerateStreamFn = nil): RunResult =
  ## Executes the plan from its cursor until the end, an abort, or an interrupt.
  var stepsRun = 0
  # Steps exchange text through a focused implicit handle. On resume, recover
  # it from the most recent completed step so Validate/Write remain useful.
  var lastOutput = ""
  for i in 0 ..< min(p.cursor, p.steps.len):
    if p.steps[i].output.len > 0:
      lastOutput = p.steps[i].output

  while not p.isDone:
    # interrupt check between steps
    if interrupt != nil and interrupt():
      p.status = psInterrupted
      result.interrupted = true
      result.stoppedAt = p.cursor
      result.stepsRun = stepsRun
      return

    # max-steps guard (a plan that never terminates must abort)
    if stepsRun >= maxSteps:
      p.status = psInterrupted
      result.aborted = true
      result.stoppedAt = p.cursor
      result.stepsRun = stepsRun
      return

    let s = p.currentStep
    s.status = ssRunning

    if sink != nil:
      sink("\n▶ " & (if s.name.len > 0: s.name else: $s.kind) & "\n")

    proc produce(prompt: string): string =
      if generateStream != nil:
        return generateStream(prompt, sink)
      if generate != nil:
        result = generate(prompt)
        emit(sink, result)
      else:
        result = "[nimo] no generator configured"
        emit(sink, result)

    case s.kind
    of skGenerate:
      s.output = produce(s.context)
      s.status = ssCompleted
    of skExtract:
      # If source is "memory", use lookupMemory instead of generate
      if s.source == "memory":
        s.output = lookupMemory(s.filter)
        s.status = ssCompleted
        emit(sink, s.output)
      else:
        var prompt = "Extract"
        if s.filter.len > 0: prompt.add(" " & s.filter)
        if s.source.len > 0: prompt.add(" from " & s.source)
        if s.forWhom.len > 0: prompt.add(" for " & s.forWhom)
        s.output = produce(prompt)
        s.status = ssCompleted
    of skSummarize:
      let prompt = "Summarize (" & s.length & "): " & s.input
      s.output = produce(prompt)
      s.status = ssCompleted
    of skValidate:
      # An empty input means "gate the previous pointed step", the normal
      # template shape: Generate -> Validate -> Write.
      let textToValidate = if s.input.len > 0: s.input else: lastOutput
      let v = validateText(textToValidate)
      s.output = "words=" & $v.wordCount & " paras=" & $v.paragraphCount &
                 " repeats=" & $v.repeatingSegments & " passed=" & $v.passed
      if v.passed: s.status = ssCompleted
      else: s.status = ssFailed
      emit(sink, s.output & "\n")
    of skWrite:
      # A write without explicit content persists the preceding step's output.
      let content = if s.content.len > 0: s.content
                    elif s.output.len > 0: s.output
                    else: lastOutput
      try:
        if s.path.len > 0:
          let dir = parentDir(s.path)
          if dir.len > 0 and dir != ".": createDir(dir)
          writeFile(s.path, content)
          s.output = "wrote " & s.path
          s.status = ssCompleted
        else:
          s.output = "no path"
          s.status = ssFailed
      except IOError as e:
        s.output = "write failed: " & e.msg
        s.status = ssFailed
      emit(sink, s.output & "\n")
    of skLoop:
      # The orchestrator (Phase 3) materializes loop fan-out before running;
      # at runtime a Loop marks its list and continues.
      s.output = "loop over: " & s.items
      s.status = ssCompleted
      emit(sink, s.output & "\n")
    of skReport:
      s.output = s.title
      s.status = ssCompleted
      emit(sink, (if s.title.len > 0: s.title else: "done") & "\n")

    if s.kind in {skGenerate, skExtract, skSummarize} and s.output.len > 0:
      lastOutput = s.output
    p.advance()
    inc stepsRun

  result.completed = true
  result.stoppedAt = p.cursor
  result.stepsRun = stepsRun