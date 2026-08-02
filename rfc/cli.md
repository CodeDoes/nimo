## What is this file for?

CLI interface, user workflow, and intent-to-DSL extraction.

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

## Intent → DSL

User gives vague intent. System extracts it into a `pipeline.nim`, then runs it.

```
$ nimo chat
> Write a cyberpunk story. Robot ninja Max. Partner Rob in chapter 2.
> Wiki for 3 chars + world. First 3 chapters. Outline to chapter 10.
> Max defeats Ghastone by chapter 10.

[nimo] Extracting intent...
[nimo] Generated: ~/.ws/myproject/pipeline.nim
[nimo] Running pipeline (wiki → extract → ch1 → ch2+outline → ch3 → finalize)...
[nimo] Done. Artifacts in ~/.ws/myproject/
```

The generated `pipeline.nim` is saved to the workspace so the user can inspect/edit it.

## Flow

1. **Capture** — user types intent in chat
2. **Extract** — LLM analyzes intent, produces a `pipeline.nim` script
3. **Save** — script written to workspace
4. **Execute** — `nim script` runs the pipeline, DAG scheduler handles dependencies
5. **Return** — artifacts served back to user

See `rfc/pipeline.md` for the DSL spec.
