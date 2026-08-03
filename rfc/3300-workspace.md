# 3300 — Workspace Pipeline

Workspace creation and initialization via pipeline.

## Commands

```bash
nimo workspace create              # Create in current dir
nimo workspace create --set-default  # Create and set as default
nimo workspace create myproject    # Create with name
nimo workspace list                # List all workspaces
nimo workspace use <path>          # Switch workspace
```

## Workspace Structure

```
~/.ws/myproject/
  ├── config.toml          # Model path, personas, settings
  ├── wiki/                # Character/world entries
  ├── chapters/            # Generated content
  └── outline.md
```

## Pipeline Example

```nim
# Initialize workspace
let setup = generate(
  """
  Create workspace at ~/.ws/myproject:
  - config.toml with model path
  - wiki/ directory
  - chapters/ directory
  """,
  target = "workspace/setup.md"
)

# Generate initial config
let config = generate(
  """
  default_workspace = ~/.ws/myproject
  personas = [user_intent, writer, editor]
  model_path = models/rwkv7-2.9b-q4.bin
  """,
  target = "workspace/config.toml"
)
```

## Workspace Modes

- **Release**: `default_workspace = .` (current directory)
- **Dev**: `default_workspace = <last_workspace>`

## See Also

- [2000-cli.md](2000-cli.md) — CLI commands
- [5000-workspace.md](5000-workspace.md) — workspace RFC
