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
| 1000 | [session.md](1000-session.md) | ✅ implemented | `src/session_manager.nim` — message tree, roles, parts |
| 1100 | [message-format.md](1100-message-format.md) | ✅ implemented | `src/harness.nim` `parseToolCalls` — the 3 tool-call forms |
| 1200 | [chat.md](1200-chat.md) | ✅ implemented | `src/chat.nim` — interactive REPL chat |
| 1300 | [story.md](1300-story.md) | ✅ implemented | `src/story.nim` — creative writing workflow |
| 2000 | [cli.md](2000-cli.md) | ✅ implemented | `src/nimo.nim` — the command surface |
| 3000 | [pipeline.md](3000-pipeline.md) | ✅ implemented | `src/pipeline.nim` — the `run_pipeline` tool |
| 3100 | [chat.md](3100-chat.md) | ✅ implemented | Chat loop: user → model → tools → answer |
| 3200 | [story.md](3200-story.md) | ✅ implemented | Story loop: outline → chapters → validate → critique |
| 3300 | [workspace.md](3300-workspace.md) | ✅ implemented | `src/workspace.nim` — workspace creation flow |
| 3400 | [agent.md](3400-agent.md) | ✅ implemented | `src/harness.nim` — the agent loop (max 8 iterations) |
| 4000 | [config.md](4000-config.md) | ✅ implemented | `src/config.nim` — `nimo.json` + `NIMO_*` env overrides |
| 5000 | [workspace.md](5000-workspace.md) | ✅ implemented | Workspace commands in `src/nimo.nim` + `src/workspace.nim` |
| 6000 | [src.md](6000-src.md) | ✅ implemented | Actual source layout (no more "desired" layout) |
| 7000 | [env.md](7000-env.md) | ✅ implemented | Build/runtime requirements, backend libraries |
| 7500 | [gpu.md](7500-gpu.md) | ✅ implemented | `src/gpu.nim` — GPU probe + backend policy |
| 8000 | [state-bake.md](8000-state-bake.md) | ✅ implemented | `src/state_cache.nim` — bake context once, resume fast |
| 8100 | [rwkv.md](8100-rwkv.md) | ✅ implemented | RWKV model details, sampling, quant formats |
| 8150 | [quantization.md](8150-quantization.md) | ✅ implemented | `src/model_cache.nim` — raw→quantize→cache policy |
| 9100 | [logging.md](9100-logging.md) | ✅ implemented | JSONL session files (`src/session_manager.nim`) |
| 9200 | [trace.md](9200-trace.md) | Partial | CLI progress output style (basic echo today) |
| 9300 | [eval.md](9300-eval.md) | ✅ implemented | `src/evals.nim` — 34 offline checks |
| 9400 | [test.md](9400-test.md) | ✅ implemented | Unit tests for tokenizer/model |

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
