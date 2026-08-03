# 5000 — Workspace

Workspace management commands.

## Commands

```bash
nimo workspace create              # Create workspace in cwd
nimo workspace create --set-default  # Create and set as default
nimo workspace create myproject    # Create with name
nimo workspace list                # Show all workspaces
nimo workspace use <path>          # Switch to workspace
nimo workspace remove <path>       # Delete workspace
```

## Example

```bash
$ nimo workspace create --set-default
Created: ~/.ws/20240101120000_abc123/
Set as default for cwd: /home/user/projects/myproject

$ nimo chat
# Uses ~/.ws/20240101120000_abc123/
```

## Workspace Modes

- **Release**: `default_workspace = .` (current directory)
- **Dev**: `default_workspace = <last_workspace>`

## See Also

- [2000-cli.md](2000-cli.md) — CLI commands
- [3300-workspace.md](3300-workspace.md) — workspace pipeline
