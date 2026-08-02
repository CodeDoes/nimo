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

**Release:** `default_workspace = .` (cwd)
**Dev:** `default_workspace = <last_workspace>` (from previous session)

## Intent → DSL

User gives vague intent. System extracts it into a `pipeline.nim`, then runs it.

```
$ nimo chat
> Write a cyberpunk story. Robot ninja Max. Partner Rob in chapter 2.
> Wiki for 3 chars + world. First 3 chapters. Outline to chapter 10.
> Max defeats Ghastone by chapter 10.

[nimo] Creating plan...
[nimo] Plan:
  1. Generate wiki entries (Max, Rob, Ghastone, City)
  2. Extract context buffers
  3. Write Chapter 1
  4. Write Chapter 2 + draft outline
  5. Write Chapter 3
  6. Finalize outline

[nimo] ▶ 1/6 Generating wiki entries...
[nimo] ✔ 1/6 Generating wiki entries... (3.2s)
[nimo] ▶ 2/6 Extracting context buffers...
[nimo] ✔ 2/6 Extracting context buffers... (0.8s)
[nimo] ▶ 3/6 Writing Chapter 1...
[nimo] ✔ 3/6 Writing Chapter 1... (12.4s)
...
```

The generated `pipeline.nim` is saved to the workspace so the user can inspect/edit it.

## Flow

1. **Capture** — user types intent in chat
2. **Extract** — LLM analyzes intent, produces a `pipeline.nim` script
3. **Save** — script written to workspace
4. **Execute** — `nim script` runs the pipeline, DAG scheduler handles dependencies
5. **Return** — artifacts served back to user

See `rfc/pipeline.md` for the DSL spec.
