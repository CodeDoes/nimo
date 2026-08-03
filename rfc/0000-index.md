# RFC Index

Recommendations for future features. Not implemented unless accepted.

## Numbering Scheme

| Thousand | Major Category |
|----------|---------------|
| 0 | Meta (index, this file) |
| 1 | Core — Session & Messages |
| 2 | CLI — User Interface |
| 3 | Pipeline — DSL & Execution |
| 4 | Config — Settings & Personas |
| 5 | Workspace — Project Isolation |
| 6 | Architecture — Source Structure |
| 7 | Environment — Build & Runtime |
| 8 | Model — RWKV & Quantization |
| 9 | Infrastructure — Logging, Test, Eval |

| Hundred | Minor Category |
|---------|---------------|
| 00 | Meta / Index |
| 00 | Session model |
| 10 | Message format |
| 00 | CLI commands |
| 00 | Pipeline core DSL |
| 10 | Pipeline — Chat |
| 20 | Pipeline — Story |
| 30 | Pipeline — Workspace |
| 40 | Pipeline — Agent |
| 00 | Configuration |
| 00 | Workspace ops |
| 00 | Source structure |
| 00 | Environment |
| 00 | State baking |
| 10 | RWKV model details |
| 00 | Infrastructure |
| 10 | Logging |
| 20 | Trace |
| 30 | Eval |
| 40 | Test |

## RFCs

| # | RFC | Category | Purpose |
|---|-----|----------|---------|
| 0000 | [index.md](0000-index.md) | Meta | This file |
| 0001 | [vision.md](0001-vision.md) | Meta | Product vision and examples |
| 1000 | [session.md](1000-session.md) | Core | Conversation model: messages, branches, parts |
| 1100 | [message-format.md](1100-message-format.md) | Core | Message format specs: tool calling, think blocks |
| 2000 | [cli.md](2000-cli.md) | CLI | Commands, workspace flow, intent extraction |
| 3000 | [pipeline.md](3000-pipeline.md) | Pipeline | Core DSL, execution model |
| 3100 | [chat.md](3100-chat.md) | Pipeline | Chat pipeline (tool calls, think blocks) |
| 3200 | [story.md](3200-story.md) | Pipeline | Story generation pipeline |
| 3300 | [workspace.md](3300-workspace.md) | Pipeline | Workspace management pipeline |
| 3400 | [agent.md](3400-agent.md) | Pipeline | Autonomous agent pipeline |
| 4000 | [config.md](4000-config.md) | Config | Personas, model params, BNF settings |
| 5000 | [workspace.md](5000-workspace.md) | Workspace | Create, list, dev vs release modes |
| 6000 | [src.md](6000-src.md) | Architecture | Desired source layout: lib/, app/, protocol/ |
| 7000 | [env.md](7000-env.md) | Environment | Engines, memory, storage, model paths |
| 8000 | [state-bake.md](8000-state-bake.md) | Model | State caching with model/vocab/prompt hash |
| 8100 | [rwkv.md](8100-rwkv.md) | Model | Quantization, model formats |
| 9100 | [logging.md](9100-logging.md) | Infrastructure | Log levels, targets, format |
| 9200 | [trace.md](9200-trace.md) | Infrastructure | Execution tracing, debug info |
| 9300 | [eval.md](9300-eval.md) | Infrastructure | Model evaluation, benchmarks |
| 9400 | [test.md](9400-test.md) | Infrastructure | Test suite, CI integration |

## Cross-References

```
2000-cli.md ──▶ 3000-pipeline.md (intent extraction produces pipeline.nim)
2000-cli.md ──▶ 5000-workspace.md (workspace is central to all commands)
1000-session.md ──▶ 1100-message-format.md (part types defined in session, used in chat)
3000-pipeline.md ──▶ 4000-config.md (pipeline uses config for model params)
6000-src.md ──▶ 1000-session.md (protocol/session.nim implements message model)
6000-src.md ──▶ 3000-pipeline.md (protocol/user_intent.nim = pipeline system)
7000-env.md ──▶ 8100-rwkv.md (engines map to lib/rwkv_*.so)
9100-logging.md ──▶ 9200-trace.md (trace uses logging infrastructure)
9300-eval.md ──▶ 9400-test.md (eval uses test infrastructure)
```

## Implementation Status

See [analysis/status.md](../analysis/status.md) for gap analysis.
