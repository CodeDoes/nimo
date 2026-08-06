# NIMO Usage Guide

## Quick Start

```bash
cd ~/dev/nimo
devenv shell

# Build (one-time)
nimble build

# Or just run directly (auto-compiles)
nimble harness
```

## Commands

### Interactive Agent (Recommended)
```bash
# Pre-compiled
./bin/nimo harness

# Or auto-compile
nimble harness
```
Type messages, press Enter. The agent will respond. Type `/quit` to exit.

### Generate Text
```bash
./bin/nimo generate --prompt "Hello" --max-length 10
```

### Health Check
```bash
./bin/nimo doctor
```

### Run Tests
```bash
./bin/nimo unit
```

### Create Plan from Goal
```bash
./bin/nimo new "write a poem about roses"
```
This creates a plan and saves it to `.nimo/programs/`.

## Example Session

```
$ ./bin/nimo harness

> hello
Hello! How can I help you?

> my name is Alice
Nice to meet you, Alice!

> what is my name?
Your name is Alice.
```

## Tips

- **Fresh cache**: If conversation gets weird, clear cache: `rm -rf .nimo/state-cache`
- **GPU memory**: Only one process can load the model at a time
- **Quick test**: `echo 'hi' | ./bin/nimo harness` (pipes input, exits after first response)

## Dev Workflow

```bash
# Edit code, then recompile and run
nimble harness      # compile + run harness
nimble unit         # compile + run tests
nimble generate     # compile + run generate
```

## Git Tags

```bash
# Revert to baseline
git checkout v0.9.0

# See all tags
git tag -l
```
