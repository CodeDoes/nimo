# CLI Interface

## Commands

```
nimo chat               # Interactive TUI chat
nimo chat -w ~/.ws/myproject
nimo generate <prompt>  # One-shot
nimo bake <prompt>      # Pre-bake state
nimo dashboard          # Full-screen TUI
nimo run pipeline.nim   # Execute a pipeline script
nimo workspace create --set-default
```

## Workspace

```
nimo workspace create --set-default
# → creates ~/.ws/YYYYMMddHHmmss_<random_slug>/
# → sets it as default for current dir

nimo chat
# → uses default workspace
#   release: cwd (.)
#   dev:     last workspace from previous session

nimo chat -w ~/.ws/myproject
# → explicit workspace override
```

**Release:** `default_workspace = .` (cwd)
**Dev:** `default_workspace = <last_workspace>` (from previous session)

## Intent → DSL

User gives vague intent. System extracts it into a `pipeline.nim`, then runs it.

See [pipeline.md](03-pipeline.md) for DSL spec.
See [workspace.md](06-workspace.md) for workspace commands.

## Flow

1. **Capture** — user types intent in chat
2. **Extract** — LLM analyzes intent, produces a `pipeline.nim` script
3. **Plan** — topological sort produces ordered steps with parallel groups
4. **Execute** — `nim script` runs the pipeline, shows progress per step
5. **Return** — artifacts served back to user
