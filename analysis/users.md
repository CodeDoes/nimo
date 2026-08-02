## What is this file for?

Who uses NIMO and what they need.

## User Personas

### 1. The Local LLM Enthusiast
**Goal:** Chat with a local RWKV model in their terminal.
**Needs:**
- Fast, responsive chat (`chat` binary)
- Option to pre-bake state for instant resume (`bake_state` + baked state path)
- Nice TUI with conversation history and telemetry (`nimwave_app`)
**Input:** `./chat /path/to/model.bin` or `./chat /path/to/model.bin /path/to/vocab.txt /path/to/baked_state.bin`

### 2. The Nim Developer
**Goal:** Use RWKV inference in their own Nim project.
**Needs:**
- Clean library API (`rwkv.nim`, `tokenizer.nim`, `sampling.nim`)
- Good docs on how to load a model, encode text, generate tokens
- No C++ build complexity — or at worst, a clear one-time setup
**Usage:** `import nimo/rwkv, nimo/tokenizer, nimo/sampling`

### 3. The Benchmark Hunter
**Goal:** Measure inference speed, test model quality.
**Needs:**
- `generate` for controlled text generation with timing
- `test_rwkv_full` for regression testing
- `bake_state` for state serialization benchmarks
**Input:** `./generate "Once upon a time" 128`

### 4. The Integrator
**Goal:** Embed RWKV in a larger system (web server, desktop app, agent).
**Needs:**
- `clone()` for parallel inference
- State save/load for checkpointing
- Clean error handling
**Usage:** Library API, not binaries

## Current vs. Desired Experience

| | Now | Desired |
|---|---|---|
| First run | Clone → git submodule → cmake → make → nimble build_all | Clone → nimble build_all (or download prebuilt .so) |
| Chat | `./chat model.bin vocab.txt` | `./chat model.bin` (vocab auto-discovered) |
| Understand the code | 14 files in flat `src/`, unclear boundaries | Organized by concept, clear ownership |
| Add a new app | Copy-paste init boilerplate from another binary | Call `initSession()` and implement the app logic |

## Recommended Source Layout

```
src/
├── engine/           # Core inference concepts
│   ├── config.nim    # Constants, defaults
│   ├── model.nim     # RwkvModel FFI, load, eval, state
│   ├── tokenizer.nim # encode/decode
│   ├── sampler.nim   # temperature/topP, stop sequences
│   └── session.nim   # initSession, generateTurn, finalizeTurn (DRY extraction)
├── ui/               # Presentation layer
│   ├── cli.nim       # Colored output helpers
│   └── logger.nim    # Eternal logging
├── apps/             # Standalone binaries
│   ├── main.nim      # Smoke test
│   ├── generate.nim  # Text generation
│   ├── chat.nim      # CLI chat
│   ├── bake_state.nim # State baking
│   └── dashboard.nim # TUI (was nimwave_app.nim)
└── tests/            # Test programs
    ├── test_model.nim
    └── test_tokenizer.nim
```

This maps directly to the user personas:
- **Local LLM Enthusiast** → `apps/chat.nim`, `apps/dashboard.nim`
- **Nim Developer** → `engine/` modules as a library
- **Benchmark Hunter** → `apps/generate.nim`, `tests/`
- **Integrator** → `engine/model.nim`, `engine/session.nim`
