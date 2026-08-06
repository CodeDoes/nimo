# NIMO - AI Harness for RWKV Inference

Deterministic harness wrapping non-deterministic LLM inference. Sessions follow JSONL message-tree format.

## Quick Start

```bash
# Enter dev environment
devenv shell

# Build
nimble build

# Run the interactive agent (multi-turn conversation)
./bin/nimo harness

# Generate text
./bin/nimo generate --prompt "Hello"

# Health check
./bin/nimo doctor

# Run tests
./bin/nimo unit
```

### First-time setup

```bash
# Clone and enter dev environment
git clone <repo>
cd nimo
devenv shell

# Build binaries
nimble build

# Verify GPU is working
./bin/nimo doctor

# Try the harness
./bin/nimo harness
```

### Using `nimo` without `./bin/` prefix

Add to your shell profile:
```bash
export PATH="$PATH:/path/to/nimo/bin"
```

## Features

| Feature | Status | Command |
|---------|--------|---------|
| Quantize | ✓ | `nimo quantize` |
| Generate (CUDA/CPU/Vulkan) | ✓ | `nimo generate --backend cuda` |
| Evals | ✓ (34/34) | `nimo unit` |
| Workspace | ✓ | `nimo workspace create/use/list` |
| Sessions | ✓ | Built into harness |
| Session Branching | ✓ | `session_branch.*` |
| Pipeline | ✓ | `run_pipeline` tool |
| Report | ✓ | `report.*` |
| System Instructions | ✓ | `system_instructions.*` |
| State Baking | ✓ | `nimo bake` |
| Quant Cache | ✓ | Auto via config |
| State Cache | ✓ | Auto via config |
| Context+State Cache | ✓ | `context_state_cache.*` |
| .nimo/ Folder | ✓ | Auto-created |
| Chapter Creation | ✓ | `story.createChapter` |
| Chapter Validation | ✓ | `story.validateChapter` |
| Critique Pipeline | ✓ | `story.critiqueChapter` |
| Wiki Pages | ✓ | `workspace.createWikiEntry` |
| Character State | ✓ | `memory.rememberCharacter` |
| Story Outline | ✓ | `story.generateOutline` |
| Summarize | ✓ | `story.summarizeChapter` |
| Extract Data | ✓ | `pipeline.extractStep` |
| Take Note | ✓ | Part of pipeline |
| FIAAS | ✓ | `fiaas.search` |
| Memory | ✓ | `memory.*` |

## Architecture

```
User (CLI/TUI)
    ↓
Harness (nimo)
    ├── Session Manager (message tree)
    ├── Tool Dispatcher (pipeline, bash)
    ├── Context Window Manager
    ├── Checkpoint/Resume
    └── Workload Config (chat/story)
    ↓
Model (RWKV-7)
    ├── CUDA Backend (~176ms/token)
    ├── CPU Fallback
    └── Vulkan Backend
```

## Model

- **Primary**: `models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin` (2.2 GB, Q4_K)
- **Source**: `models/rwkv7-g1i-2.9b-20260729-ctx16384-f16.bin` (5.9 GB, FP16)
- **GPU**: NVIDIA GeForce RTX 2050 (4 GB VRAM)

## Workload Modes

| Mode | Temp | Context | Tools |
|------|------|---------|-------|
| Chat | 0.0-0.3 | Aggressive pruning | Full |
| Story | 0.7-1.0 | Global continuity | Memory retrieval |
| Pipeline | 0.5-0.7 | Step-by-step | File I/O |

## Commands

```bash
# Core
nimo generate --backend cuda --model <path> --prompt "text"
nimo chat --backend cuda <model>
nimo quantize <input> <format> <output>
nimo unit

# Workspace
nimo workspace create <name>
nimo workspace use <name>
nimo workspace list
nimo workspace status

# Story
nimo story generate <premise> --workspace <name>
nimo story validate <chapter> --workspace <name>
nimo story critique <chapter> --workspace <name>

# Harness
nimo harness
```

## Validation

```bash
# Run all tests
./scripts/e2e_demo.sh

# Run evals
nimo unit  # 34/34 passed

# Test CUDA
nimo generate --backend cuda --model models/*.q4k.bin --prompt "Test" --max-length 10
# Output: Generated 10 tokens in ~2s (200ms/token)
```

## Plans

All plans in `plan/` are complete:
- 0001-0003: CUDA validation
- 0004: Workspace management
- 0005: Story pipeline
- 0006: Session branching
- 0007: Memory system
- 0008-0010: Documentation and future work

## Git History

```bash
git log --oneline  # 111+ commits
```

## License

MIT
