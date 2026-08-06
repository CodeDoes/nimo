# NIMO Usage Guide

## Quick Start

```bash
cd ~/dev/nimo
devenv shell
```

## Commands (All via nimble)

### Interactive Agent
```bash
nimble run harness
```

### Generate Text
```bash
nimble run generate -- --prompt "Hello" --max-length 10
```

### Health Check
```bash
nimble run nimo doctor
```

### Run Tests
```bash
nimble unit
```

### Create Plan from Goal
```bash
nimble run nimo new "write a poem about roses"
```

### Chat (simple)
```bash
nimble run chat
```

## Example Session

```bash
$ nimble run harness

nimo harness — user -> pipeline -> tool call -> answer
Config file: nimo.json
Type /quit to exit, /save <file> to save session.

> hello
Hello! How can I help you?

> my name is Alice
Nice to meet you, Alice!

> what is my name?
Your name is Alice.

> /quit
```

## Tips

- **Fresh cache**: If conversation gets weird, clear cache: `rm -rf .nimo/state-cache`
- **GPU memory**: Only one process can load the model at a time
- **Quick test**: `echo 'hi' | nimble run harness`

## Dev Workflow

```bash
# Edit code, then recompile and run
nimble run harness
nimble unit
nimble run generate -- --prompt "Hello"
```

## Git Tags

```bash
# Revert to baseline
git checkout v0.9.0

# See all tags
git tag -l
```
