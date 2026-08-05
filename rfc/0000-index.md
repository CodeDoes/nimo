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

| Number | Title | Summary |
|--------|-------|---------|
| 0000 | [Index](0000-index.md) | Design documents for the NIMO project. |
| 0001 | [Vision](0001-vision.md) | NIMO is an AI Harness — deterministic software wrapping non-deterministic LLM inference. |
| 1000 | [Session](1000-session.md) | The conversation container. |
| 1100 | [Message Format](1100-message-format.md) | Raw text format for each content type, and the **planner's emission format**. |
| 1200 | [Chat](1200-chat.md) | The interactive chat workflow. |
| 1300 | [Story](1300-story.md) | The creative writing workflow. |
| 2000 | [CLI](2000-cli.md) | The command surface. |
| 3000 | [Pipeline](3000-pipeline.md) | Intent → plan → execute. |
| 3100 | [Chat Pipeline](3100-chat.md) | The interactive chat loop with plan compilation. |
| 3200 | [Story Pipeline](3200-story.md) | Multi-chapter story generation with validation. |
| 3300 | [Workspace Pipeline](3300-workspace.md) | Workspace creation and structure. |
| 3400 | [Agent](3400-agent.md) | The orchestration loop. |
| 3500 | [Plan Format](3500-plan-format.md) | The plan is the core artifact: it's what the planner emits and what the executor runs. |
| 3600 | [Engine](3600-engine.md) | The engine is the executor that takes a plan and runs it — **forever if needed** — streaming every token, checkpointing for resume, and allowing interruption. |
| 4000 | [Config](4000-config.md) | How settings are resolved. |
| 5000 | [Workspace](5000-workspace.md) | Workspace management commands and the active-workspace pointer. |
| 6000 | [Source Structure](6000-src.md) | The actual layout of `src/`. |
| 7000 | [Environment](7000-env.md) | Build and runtime requirements. |
| 7500 | [GPU Detection & Backend Policy](7500-gpu.md) | How the harness determines GPU usability and decides—before loading the model— whether to use GPU, fall back to CPU, or refuse to start. |
| 8000 | [State Bake](8000-state-bake.md) | Bake a context into model state so later sessions resume instantly, and **bake skills** — the state-tuning mechanism. |
| 8100 | [RWKV](8100-rwkv.md) | RWKV model details. |
| 8150 | [Quantization](8150-quantization.md) | Model quantization policy and the model cache. |
| 9100 | [Logging](9100-logging.md) | JSONL files. |
| 9200 | [Trace](9200-trace.md) | What the user sees in the CLI during execution. |
| 9300 | [Eval](9300-eval.md) | Check that the harness behaves correctly. |
| 9400 | [Test](9400-test.md) | Test if the harness (code) is working. |

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
