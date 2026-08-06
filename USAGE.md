# NIMO Usage Guide

## Quick Start

```bash
cd ~/dev/nimo
devenv shell
```

## Commands (via devenv)

### Interactive Agent
```bash
devenv shell nimo-harness
```

### Generate Text
```bash
devenv shell nimo-generate -- --prompt "Hello" --max-length 10
```

### Health Check
```bash
devenv shell nimo-doctor
```

### Run Tests
```bash
devenv shell nimo-unit
```

### Create Plan from Goal
```bash
devenv shell nimo-new "write a poem about roses"
```

### Chat (simple)
```bash
devenv shell nimo-chat --backend cuda models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin
```

## Example Session

```bash
$ devenv shell nimo-harness

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
- **Quick test**: `echo 'hi' | devenv shell nimo-harness`

## Dev Workflow

```bash
# Edit code, then recompile and run
devenv shell nimo-harness
devenv shell nimo-unit
devenv shell nimo-generate -- --prompt "Hello"
```

## Git Tags

```bash
# Revert to baseline
git checkout v0.9.0

# See all tags
git tag -l
```
