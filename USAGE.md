# NIMO Usage Guide

## Quick Start

```bash
cd ~/dev/nimo
devenv shell
```

## Commands

### Dev Workflow (Auto-compile)
```bash
# Compile and run harness
nimble run harness

# Compile and run unit tests
nimble run unit

# Compile and run generate
nimble run generate -- --prompt "Hello" --max-length 10
```

### Pre-compiled (Faster)
```bash
./bin/nimo harness
./bin/nimo generate --prompt "Hello"
./bin/nimo doctor
./bin/nimo unit
./bin/nimo new "write a poem"
```

### Interactive Agent
```bash
# Dev workflow
nimble run harness

# Or pre-compiled
./bin/nimo harness
```
Type messages, press Enter. Type `/quit` to exit.

### Example Session
```
$ nimble run harness

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

## Git Tags

```bash
# Revert to baseline
git checkout v0.9.0

# See all tags
git tag -l
```
