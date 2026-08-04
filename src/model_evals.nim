## Model Evals - Black-box model probes (RFC 9700)
##
## Tests the MODEL's behavior, not our code.
## Unlike unit tests (deterministic, offline), model evals are probabilistic
## and require the real model + backend.
##
## Usage: nimo model-eval [options]
## - Runs fixed prompts through the model
## - Reports rates over N trials
## - Saves artifacts to .nimo/model-evals/

import std/[os, strutils, times, json]
import ./config, ./bootstrap, ./session_manager

type
  EvalResult* = object
    name*: string
    rate*: float      # success rate (0.0 to 1.0)
    trials*: int
    success*: int
    fail*: int

proc runModelEval*(cfg: NimoConfig, cwd: string = "."): int =
  ## Runs the model eval harness.
  ## TODO: Implement fixed prompt set + rate reporting.
  echo "[model-eval] Placeholder - implementing..."
  echo "[model-eval] To run: nimo model-eval --prompt-set fixed"
  return 0

proc main() =
  let args = commandLineParams()
  if args.len == 0:
    echo """nimo model-eval — Black-box model probes

Usage:
  nimo model-eval                    # Run all evals
  nimo model-eval --prompt-set fixed # Run with fixed prompts
  nimo model-eval --trials N         # Set number of trials (default: 10)
"""
    quit(0)

  var cfg = loadConfig()
  let bs = bootstrapSession(cfg, getCurrentDir())
  for line in bs.lines: echo line
  if not bs.ok: return

  discard runModelEval(cfg, getCurrentDir())

when isMainModule:
  main()
