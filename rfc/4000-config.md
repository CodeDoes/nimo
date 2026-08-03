# 4000 — Config

What's in `config.toml` for a workspace.

## Example config.toml

```toml
# Paths
default_workspace = "~/.ws"
model_path = "models/rwkv7-2.9b-q4.bin"
vocab_path = "rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt"

# Model parameters
temperature = 0.7
top_p = 0.9
max_tokens = 200
stop_sequences = ["\n\nUser:", "\n\nAssistant:"]

# Personas (which prompt templates to use)
personas = ["user_intent", "writer", "editor"]

# Engine
engine = "cuda"  # cuda, vulkan, cpu

# Logging
log_level = "info"  # trace, debug, info, warn, error
```

## Personas

| Persona | Purpose |
|---------|---------|
| `user_intent` | Parse vague user requests into structured tasks |
| `writer` | Generate creative content |
| `editor` | Refine and improve content |
| `critique` | Evaluate quality |
| `planner` | Create execution plans |
| `coder` | Generate code |

## See Also

- [7000-env.md](7000-env.md) — engine options
- [3000-pipeline.md](3000-pipeline.md) — config used by pipelines
