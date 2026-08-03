# NIMO — src/ vs rfc/src.md

## The Intent Protocol

`protocol/user_intent.nim` is the pipeline system. Per `rfc/pipeline.md`:

```
User intent -> LLM extracts pipeline.nim -> DAG execution -> artifacts
```

The pipeline DSL (`generate`, `extract`, `summarize` procs) is the execution layer for the intent protocol.

## Desired Structure (rfc/src.md)

```
lib/
  rwkv.so           — base engine
  rwkv_cuda.so      — CUDA backend
  rwkv_vulkan.so    — Vulkan backend (not yet)
  nimo.so           — shared Nim library (not yet)

app/
  cli.nim           — entry point
  server.nim        — (not yet)
  client.nim        — (not yet)
  session.nim       — message/branch/part model (not yet)
  rwkv.nim          — FFI bridge
  model.nim         — model abstraction (not yet, rwkv.nim covers this)
  tokenizer.nim     — tokenization
  protocol/
    user_intent.nim    = pipeline system (rfc/pipeline.md)
    just_chatting.nim  = chat with tool/think (rfc/session.md + rfc/chat.md)
    workspace_related.nim = workspace ops (rfc/workspace.md)
    story_related.nim    = story generation flow (example in rfc/cli.md)
```

## Current Structure (src/)

```
rwkv.nim          — FFI bridge
tokenizer.nim     — tokenization
sampling.nim      — temperature/topP
config.nim        — constants
session.nim       — raw inference handle (NOT the RFC session model)
cli.nim           — colored output helpers
logger.nim        — eternal logging
macros.nim        — withModel, timeBlock, checkOk, streamToken

main.nim          — smoke test
generate.nim      — one-shot text gen
chat.nim          — raw REPL chat (no tool/think)
bake_state.nim    — prompt -> binary state
nimwave_app.nim   — TUI dashboard

test_rwkv_full.nim
test_tokenizer.nim
```

## Key Gaps

| RFC Module | Status | Notes |
|------------|--------|-------|
| `lib/nimo.so` | ❌ | No shared library, all executables |
| `lib/rwkv_vulkan.so` | ❌ | Only CUDA backend exists |
| `app/server.nim` | ❌ | Not implemented |
| `app/client.nim` | ❌ | Not implemented |
| `protocol/user_intent.nim` | ❌ | = pipeline system from rfc/pipeline.md |
| `protocol/just_chatting.nim` | ❌ | chat.nim is raw REPL, no tool/think |
| `protocol/workspace_related.nim` | ❌ | Not implemented |
| `protocol/story_related.nim` | ❌ | Not implemented |
| `session.nim` (message model) | ❌ | Current is raw inference, not messages/branches/parts |

## Current vs RFC `session.nim`

| RFC `session.nim` | Actual `session.nim` |
|---|---|
| Session = messages[] + branches[] | Session = {model, tok, state, logits, rng} |
| Message = part_type + part_content | No message model |
| Parts: system/user/think/tool_call/tool_result/text | Returns raw string from generateTurn |

Same name, different purpose.

## First Implementation Priority

1. **`protocol/user_intent.nim`** — the pipeline system (rfc/pipeline.md)
2. **`session.nim` rewrite** — message/branch/part model (rfc/session.md)
3. **`protocol/just_chatting.nim`** — chat with tool/think (rfc/chat.md)
4. **`protocol/workspace_related.nim`** — workspace ops (rfc/workspace.md)
5. **Build shared library** — `lib/nimo.so`
