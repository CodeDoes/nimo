# RFC Index

Design documents for the NIMO project. Each RFC below has been aligned with
the **actual code** in `src/` and includes an implementation status. The
status of the whole project is tracked in [analysis/status.md](../analysis/status.md).

## Numbering Scheme

| Thousand | Major Category |
|----------|---------------|
| 0 | Meta (index, vision) |
| 1 | Core — Session & Messages |
| 2 | CLI — User Interface |
| 3 | Pipeline — Execution & Tools |
| 4 | Config — Settings |
| 5 | Workspace — Project Isolation |
| 6 | Architecture — Source Structure |
| 7 | Environment — Build & Runtime |
| 8 | Model — RWKV & Quantization |
| 9 | Infrastructure — Logging, Eval, Test |

## RFCs

| # | RFC | Status | What it describes (in code) |
|---|-----|--------|------------------------------|
| 0000 | [index.md](0000-index.md) | — | This file |
| 0001 | [vision.md](0001-vision.md) | Guide | Product vision: harness around a model |
| 1000 | [session.md](1000-session.md) | ⏳ re-scoped | thin session: history + refs; provenance (model/bake per message) |
| 1100 | [message-format.md](1100-message-format.md) | ✅ implemented | `src/harness.nim` `parseToolCalls` — the 3 tool-call forms |
| 1200 | [chat.md](1200-chat.md) | ✅ implemented | `src/chat.nim` — interactive REPL chat (streaming migration pending, RFC 3600) |
| 1300 | [story.md](1300-story.md) | Partial | Story flow — hardcoded approx.; target is the plan-template form |
| 2000 | [cli.md](2000-cli.md) | ⏳ re-scoped | goal-first verbs (new/open/continue/plan/run); no content-type nouns |
| 3000 | [pipeline.md](3000-pipeline.md) | Partial | `src/pipeline.nim` — intent → plan → execute (MVP step superseded) |
| 3100 | [chat.md](3100-chat.md) | Superseded | Target: every message compiles into a streaming engine (code in transition) |
| 3200 | [story.md](3200-story.md) | Partial | Story plan template: outline → extract → wiki → chapters → validate |
| 3300 | [workspace.md](3300-workspace.md) | ✅ implemented | `src/workspace.nim` — workspace creation flow |
| 3400 | [agent.md](3400-agent.md) | Superseded | Target: planner → plan → engine (old improvisation loop being removed) |
| 3500 | [plan-format.md](3500-plan-format.md) | Design ref | The plan artifact: step vocabulary, data-driven loops, plan-as-data |
| 3600 | [engine.md](3600-engine.md) | Design ref | The streaming executor: sink, infinite loop, checkpoint/resume |
| 4000 | [config.md](4000-config.md) | ✅ implemented | `src/config.nim` — `nimo.json` + `NIMO_*` env overrides |
| 5000 | [workspace.md](5000-workspace.md) | ✅ implemented | Workspace commands in `src/nimo.nim` + `src/workspace.nim` |
| 6000 | [src.md](6000-src.md) | ✅ implemented | Actual source layout (no more "desired" layout) |
| 7000 | [env.md](7000-env.md) | ✅ implemented | Build/runtime requirements, backend libraries |
| 7500 | [gpu.md](7500-gpu.md) | ✅ implemented | `src/gpu.nim` — GPU probe + backend policy |
| 8000 | [state-bake.md](8000-state-bake.md) | Partial | `src/state_cache.nim` — context bake; skill bake (planner/output) planned |
| 8100 | [rwkv.md](8100-rwkv.md) | ✅ implemented | RWKV model details, sampling, quant formats |
| 8150 | [quantization.md](8150-quantization.md) | ✅ implemented | `src/model_cache.nim` — raw→quantize→cache policy |
| 9100 | [logging.md](9100-logging.md) | ✅ implemented | JSONL session files (`src/session_manager.nim`) |
| 9200 | [trace.md](9200-trace.md) | Partial | CLI progress: token streaming (generate) + target ▶/✔ steps |
| 9300 | [eval.md](9300-eval.md) | ✅ implemented | `src/evals.nim` — 34 offline checks |
| 9400 | [test.md](9400-test.md) | ✅ implemented | Unit tests for tokenizer/model |

## Wild research RFCs (9500 series)

These are intentionally ambitious, **speculative** proposals. They are not a
shipping roadmap or implementation claim; each begins with offline fixtures,
behavioral tests, and an explicit implementation plan before it may affect a
workspace.

| # | RFC | Theme |
|---|-----|-------|
| 9500 | [living-worlds.md](9500-living-worlds.md) | append-only world facts and continuity pulse |
| 9510 | [time-travel-debugging.md](9510-time-travel-debugging.md) | replay and causal plan forks |
| 9520 | [dream-compiler.md](9520-dream-compiler.md) | competing plans before expensive work |
| 9530 | [agent-biomes.md](9530-agent-biomes.md) | bounded specialist ecosystems |
| 9540 | [narrative-physics.md](9540-narrative-physics.md) | simulated story constraints |
| 9550 | [memory-ecology.md](9550-memory-ecology.md) | memory lineage, decay, and review |
| 9560 | [ontological-git.md](9560-ontological-git.md) | semantic claim diffs |
| 9570 | [blackboard-cities.md](9570-blackboard-cities.md) | typed public coordination notices |
| 9580 | [counterfactual-labs.md](9580-counterfactual-labs.md) | isolated what-if branches |
| 9590 | [adversarial-muse.md](9590-adversarial-muse.md) | bounded creative opposition |
| 9600 | [midnight-shift.md](9600-midnight-shift.md) | read-only overnight maintenance |
| 9610 | [simulation-forges.md](9610-simulation-forges.md) | sandboxed plan scenarios |
| 9620 | [skill-genomes.md](9620-skill-genomes.md) | provenance-rich baked skills |
| 9630 | [plurality-court.md](9630-plurality-court.md) | cited deliberation for high-impact work |
| 9640 | [attention-weather.md](9640-attention-weather.md) | visible focused-context diagnostics |
| 9650 | [artifact-economy.md](9650-artifact-economy.md) | explicit local execution budgets |
| 9660 | [ritual-interfaces.md](9660-ritual-interfaces.md) | human-gated workflow templates |
| 9670 | [embodied-workspaces.md](9670-embodied-workspaces.md) | one event stream, many accessible views |
| 9680 | [mythic-observability.md](9680-mythic-observability.md) | poetic but exact run traces |
| 9690 | [consentful-autonomy.md](9690-consentful-autonomy.md) | revocable capability grants |

## Cross-References

```
2000-cli.md ──▶ 5000-workspace.md + 3300-workspace.md (workspace commands)
1000-session.md ──▶ 1100-message-format.md (message parts used by tool calls)
3400-agent.md ──▶ 3000-pipeline.md (the agent loop executes the pipeline tool)
3000-pipeline.md ──▶ 4000-config.md (pipeline uses config for generation params)
3200-story.md ──▶ 1000-session.md (story generation runs through sessions)
3200-story.md ──▶ 3300-workspace.md (chapters/wikis live in a workspace)
8000-state-bake.md ──▶ 8150-quantization.md (model cache + state cache both live in .nimo/)
7500-gpu.md ──▶ 4000-config.md (backend / gpuLayers config keys)
9300-eval.md ──▶ 9400-test.md (evals build on the same offline harness)
```

## Implementation Status

All RFCs marked ✅ are implemented in `src/` and covered by the offline test
suite (`nimo eval`, 34 checks). See [analysis/status.md](../analysis/status.md)
for the module-by-module map and known gaps.
