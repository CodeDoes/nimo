# Workspace Pipeline

Workspace management pipeline.

## Operations

- `workspace create` — create new workspace
- `workspace create --set-default` — create and set as default
- `workspace use <path>` — switch to existing workspace
- `workspace list` — list all workspaces
- `workspace remove <path>` — remove a workspace

## Pipeline Example

```nim
# Create workspace pipeline
let ws = generate(
  """
  Create workspace at ~/.ws/myproject
  Initialize with:
    - config.toml (model path, personas)
    - wiki/ (empty dir for character/world entries)
    - chapters/ (empty dir for story output)
  """,
  target = "workspace/setup.md"
)

# Populate workspace
let setup = generate(
  """
  Generate initial config for workspace:
    - default_workspace = ~/.ws/myproject
    - personas = [user_intent, writer, editor]
    - model_path = models/rwkv7-2.9b-q4.bin
  """,
  target = "workspace/config.toml"
)
```

## Workspace States

- **release**: `default_workspace = .` (cwd)
- **dev**: `default_workspace = <last_workspace>` (from previous session)

## See Also

- [5000-workspace.md](5000-workspace.md) — workspace commands
- [3000-pipeline.md](3000-pipeline.md) — core DSL
