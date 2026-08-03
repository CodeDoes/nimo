# Plan: Workspace Management

## Goal

Implement workspace creation, management, and persistence per RFC 5000/3300.

## Workspace Structure

```
~/.ws/<workspace-name>/
  ├── config.toml          # Model path, personas, settings
  ├── wiki/                # Character/world entries
  │   └── *.md
  ├── chapters/            # Generated content
  │   └── *.md
  ├── outline.md           # Story outline
  └── sessions/            # JSONL session files
      └── *.jsonl
```

## Commands

```bash
nimo workspace create [NAME]      # Create new workspace
nimo workspace create --set-default [NAME]
nimo workspace list               # List all workspaces
nimo workspace use <path|name>    # Switch workspace
nimo workspace remove <path|name> # Delete workspace
nimo workspace status             # Show current workspace
```

## Implementation

1. `src/workspace.nim` - Workspace management module
2. Update `nimo.nim` CLI to add workspace subcommand
3. Update `config.nim` to support workspace path
4. Create default workspace template

## Validation

- Create workspace, verify structure
- List workspaces
- Switch workspace, verify config loaded
- Remove workspace
