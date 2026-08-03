# Plan: Session Branching

## Goal

Implement session branching per RFC 1000 for alternative conversation paths.

## Data Model

```
Session
  ├── id
  ├── messages: [Message]
  └── branches: [Branch]
       ├── id
       ├── parentMessageId
       └── messages: [Message]
```

## Commands

```bash
nimo session branch --from msg_id
nimo session switch <branch_id>
nimo session list
nimo session merge <branch_id>
```

## Implementation

1. Extend `session_manager.nim` with branch support
2. Add branch commands to CLI
3. Implement branch visualization
