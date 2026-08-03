# Source Structure

Desired layout for the project.

```
lib/
  rwkv.so           — base engine
  rwkv_cuda.so      — CUDA backend
  rwkv_vulkan.so    — Vulkan backend
  nimo.so           — shared Nim library

app/
  cli.nim           — CLI entry point
  server.nim        — network server
  client.nim        — network client
  session.nim       — session management (message/branch/part model)
  rwkv.nim          — FFI bridge
  model.nim         — model abstraction
  tokenizer.nim     — tokenization
  protocol/
    user_intent.nim      — intent -> pipeline.nim -> execute
    just_chatting.nim    — plain chat (tool calls, think)
    workspace_related.nim — workspace ops
    story_related.nim     — story generation flow
```

## See Also

- [session.md](01-session.md) — `app/session.nim` implements this model
- [pipeline.md](03-pipeline.md) — `protocol/user_intent.nim` implements this
- [chat.md](04-chat.md) — `protocol/just_chatting.nim` implements this
- [env.md](09-env.md) — engines map to `lib/rwkv_*.so`
