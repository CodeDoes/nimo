# RFC Index

Recommendations for future features. Not implemented unless accepted.

## Numbering Scheme

```
0000-0999  Meta (index, this file)
1000-1999  Session/Chat (conversation model, message parts)
2000-2999  CLI (user interface, commands)
3000-3999  Pipeline (DSL, execution)
4000-4999  Config (settings, personas)
5000-5999  Workspace (project isolation)
6000-6999  Architecture (source structure)
7000-7999  Environment (build, runtime)
8000-8999  RWKV (model, quantization, state baking)
9000-9999  Infrastructure (agent, logging, trace, eval, test)
```

## RFCs

| # | RFC | Category | Purpose |
|---|-----|----------|---------|
| 0000 | [index.md](0000-index.md) | Meta | This file |
| 1000 | [session.md](1000-session.md) | Session | Conversation model: messages, branches, parts |
| 1100 | [message-format.md](1100-message-format.md) | Message Format | Message format specs: tool calling, think blocks |
| 2000 | [cli.md](2000-cli.md) | CLI | Commands, workspace flow, intent extraction |
| 3000 | [pipeline.md](3000-pipeline.md) | Pipeline | Core DSL, execution model |
| 3110 | [chat.md](3110-chat.md) | Pipeline | Chat pipeline (tool calls, think blocks) |
| 3111 | [story.md](3111-story.md) | Pipeline | Story generation pipeline |
| 3112 | [workspace.md](3112-workspace.md) | Pipeline | Workspace management pipeline |
| 3113 | [agent.md](3113-agent.md) | Pipeline | Autonomous agent pipeline |
| 4000 | [config.md](4000-config.md) | Config | Personas, model params, BNF settings |
| 5000 | [workspace.md](5000-workspace.md) | Workspace | Create, list, dev vs release modes |
| 6000 | [src.md](6000-src.md) | Architecture | Desired source layout: lib/, app/, protocol/ |
| 7000 | [env.md](7000-env.md) | Environment | Engines, memory, storage, model paths |
| 8000 | [state-bake.md](8000-state-bake.md) | RWKV | State caching with model/vocab/prompt hash |
| 8100 | [rwkv.md](8100-rwkv.md) | RWKV | Quantization, model formats |
| 9000 | [agent.md](9000-agent.md) | Infrastructure | Agent concept |
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
