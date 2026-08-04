# 5000 — Workspace

Workspace management commands and the active-workspace pointer.
**Status: implemented** in `src/nimo.nim` (workspace command) and
`src/workspace.nim`.

## Commands

```bash
nimo workspace create [NAME] [--set-default]
nimo workspace list
nimo workspace use <name|path>
nimo workspace status
nimo workspace remove <name|path>
```

## The active-workspace pointer

The current directory can remember which workspace it belongs to via a small
file named `.nimo-workspace`:

1. `nimo workspace use <name>` (or `create --set-default`) writes the absolute
   workspace path into `.nimo-workspace`.
2. `nimo workspace status` reads that file and reports the active workspace
   plus item counts for `wiki/ chapters/ sessions/ .nimo/`.
3. Other tools can read it through `getDefaultWorkspace()` to know which
   workspace to work in.

## Example

```bash
$ nimo workspace create my_story --set-default
[workspace] Creating workspace: my_story
[workspace] Created: /home/user/.ws/my_story
[workspace] Set as default for: /home/user/projects/nimo

$ nimo workspace status
[workspace] Current: /home/user/.ws/my_story
  wiki/ (0 items)
  chapters/ (0 items)
  sessions/ (0 items)
  .nimo/ (2 items)

$ nimo workspace list
[workspace] Available workspaces:
  my_story
```

## Removal

`nimo workspace remove <name>` finds the workspace (by name under `~/.ws/` or
by direct path) and deletes the directory. There is no undo — files are gone.

## See Also

- [3300-workspace.md](3300-workspace.md) — workspace structure & creation flow
- [2000-cli.md](2000-cli.md) — full command reference
