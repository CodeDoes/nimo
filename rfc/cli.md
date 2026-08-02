## CLI Interface

### Commands

```
nimo chat                  # Interactive TUI chat (default workspace: cwd)
nimo chat -w ~/.ws/myproject   # Chat in specific workspace
nimo generate <prompt>     # One-shot text generation
nimo bake <prompt>         # Pre-bake model state
nimo dashboard             # Full-screen TUI dashboard
```

### Workspace Concept

Workspaces are directories containing story/state artifacts:
```
~/.ws/myproject/
├── wiki/           # Character and world entries
├── chapters/       # Generated chapters
├── outline.md      # Story outline
└── decisions.md    # High-level creative decisions
```

### User Intent Flow

1. **Vague intent** → "Write a story about a robot ninja"
2. **Clarification** → System asks about tone, setting, scope
3. **Codification** → Intent becomes a structured pipeline (see `rfc/pipeline.md`)
4. **Execution** → Pipeline runs, artifacts are saved to workspace
5. **Iteration** → User can refine ("make it darker", "continue the next chapter")

### Example Interaction

```
$ nimo chat
> Write a story about a robot ninja named Max.
> He has a partner called Rob introduced in chapter 2.
> Create a wiki for 3 characters and the world.
> Write the first 3 chapters and outline to chapter 10.

[nimo] I'll create a cyberpunk narrative pipeline.
[nimo] Generating wiki entries in parallel...
[nimo] Writing chapters with targeted context...
[nimo] Done! Artifacts saved to ./workspace/
```

### Pipeline Integration

The pipeline DSL (see `rfc/pipeline.md`) is the execution layer behind complex `nimo chat` requests. When the user gives a multi-step request, nimo:
1. Parses the intent
2. Builds a DAG of `generate`/`extract`/`summarize` nodes
3. Executes with topological scheduling
4. Saves artifacts to the workspace
