## What is this file for?

CLI interface and user workflow.

## Commands

```
nimo chat               # Interactive TUI chat (default workspace: cwd)
nimo chat -w ~/.ws/myproject
nimo generate <prompt>  # One-shot generation
nimo bake <prompt>      # Pre-bake state
nimo dashboard          # Full-screen TUI
nimo run pipeline.nim   # Execute a pipeline DSL script
```

## Workspace

```
~/.ws/myproject/
├── wiki/           # Character/world entries
├── chapters/       # Generated chapters
├── outline.md      # Story outline
└── decisions.md    # Creative decisions
```

## User Flow

```
$ nimo chat
> Write a cyberpunk story. Robot ninja Max. Partner Rob in chapter 2.
> Wiki for 3 chars + world. First 3 chapters. Outline to chapter 10.

[nimo] Building pipeline...
[nimo] Running: wiki (4 parallel) → extract → ch1 → ch2, outline (parallel) → ch3 → finalize
[nimo] Done. Artifacts in ./workspace/
```

## Pipeline Integration

`nimo run pipeline.nim` executes a NimScript DSL (see `rfc/pipeline.md`).
Complex `nimo chat` requests auto-generate and run a pipeline behind the scenes.
