# 3300 — Workspace Pipeline

Workspace creation and structure. **Status: implemented** in
`src/workspace.nim` and the `workspace` command in `src/nimo.nim`.

## What a workspace is

A workspace is a self-contained project folder that keeps a story/writing
project's files together: characters, world notes, chapters, sessions, and
caches. Workspaces live under `~/.ws/<name>/`.

## Workspace structure (as created)

```
~/.ws/<name>/
  config.toml            # model path, generation params, story rules
  outline.md             # story outline template
  wiki/                  # character & world entries (markdown)
  chapters/              # generated chapters (01_..., 02_...)
  sessions/              # saved conversations
  .nimo/
    model-cache/         # quantized model cache
    state-cache/         # baked state cache
```

## How creation works (step by step)

`newWorkspace(name)`:

1. Create the base directory `~/.ws/<name>/`.
2. Create `wiki/`, `chapters/`, `sessions/`, `.nimo/` (with
   `model-cache/` and `state-cache/`).
3. Write `config.toml` with sensible defaults: model path, vocab, temperature
   0.7, topP 0.7, maxTokens 200, backend cuda, gpuLayers 99, story rules
   (minChapterWords 500, minParagraphs 5, maxRepeats 3), pipeline limits.
4. Write `outline.md` with a story-outline template (title, logline,
   characters, world, plot, chapters, themes).

## Commands

```
nimo workspace create [NAME] [--set-default]
nimo workspace list
nimo workspace use <name|path>
nimo workspace status
nimo workspace remove <name|path>
```

- `create` — as above. `--set-default` also writes the workspace path into
  `.nimo-workspace` in the current directory.
- `list` — walks `~/.ws/` and shows every folder with a `config.toml`.
- `use` — writes the chosen workspace path into `.nimo-workspace` (the
  current-directory pointer).
- `status` — reads `.nimo-workspace` and prints the active workspace with item
  counts for each subfolder.
- `remove` — deletes the workspace directory (after finding it by name/path).

## Library helpers (for other modules)

- `findWorkspace(nameOrPath)` — resolve a name or path to a `Workspace`.
- `listWorkspaces()` — all workspaces.
- `createWikiEntry(ws, name, content)` — writes `wiki/<name>.md`.
- `createChapter(ws, number, title, content)` — writes `chapters/0N_<title>.md`.
- `readChapter(ws, number)` / `listChapters(ws)` — read/list chapter files.
- `workspaceStatus(ws)` — prints the status block.
- `setDefaultWorkspace` / `getDefaultWorkspace` — read/write the
  `.nimo-workspace` pointer.

## See Also

- [5000-workspace.md](5000-workspace.md) — workspace command details
- [3200-story.md](3200-story.md) — chapters/wikis generated into a workspace
- [2000-cli.md](2000-cli.md) — the command surface
