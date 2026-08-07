# nimo — Complete Capability Inventory

> Everything the system can do (or is designed to do). Categorized, with status.

## 1. Interactive agent surfaces (CLI)

| Command | What it does | Status |
|---------|--------------|--------|
| `nimo chat` | Interactive agent loop (legacy, bare `/reset` + `/quit`; no plan/tool) | ⚠️ superseded by harness/repl; to be folded into unified chat (RFC 2111) |
| `nimo harness` | Full agent loop: bare text → plan → tool calls → answer. Session JSONL. | ✅ implemented |
| `nimo repl` | Command shell (`/send /steer /queue /flush /plan /ws /session /story /state /cuda`) | ✅ implemented (folded into RFC 2111 `chat` as the `/` dialect) |
| `nimo --help` | Lists all commands | ✅ implemented |

## 2. One-shot / scripted generation

| Command | What it does | Status |
|---------|--------------|--------|
| `nimo generate --prompt "..." --max-tokens N --backend cuda` | Single turn generation, streams tokens | ✅ implemented |
| `nimo generate --smoke --prompt "..." --max-tokens N` | Smoke test: loads model, generates N tokens, reports PASS/FAIL + wall time | ✅ implemented |
| `nimo model-eval` | Planner compilation evals (offline, deterministic, 5 trials) | ✅ implemented |
| `nimo model-eval --scored --trials N --seed S` | Model-as-judge scored evals (real model, bake judge state, 0-10 scores) | ✅ implemented |
| `nimo model-eval --scored --baseline results.json` | Delta vs saved baseline (continuous, DEGRADED/improved flags) | ✅ implemented |
| `nimo model-eval --scored --save results.json` | Save scored eval results | ✅ implemented |

## 3. State bake / model management

| Command | What it does | Status |
|---------|--------------|--------|
| `nimo bake <model> <prompt> [out.state] [vocab]` | Bake a prompt into model state (resume-ready state vector) | ✅ implemented |
| `nimo quantize <input.bin> <format> <output.bin>` | Convert raw model to quantized format (Q4_K, Q5_K, Q6_K, Q8_0…) | ✅ implemented |
| `nimo doctor` | GPU probe + librwkv.so + model file + workspace sanity check | ✅ implemented |
| `nimo new "<goal>"` | `interpret(goal)` → plan JSON saved to `.nimo/programs/`; prints plan + path | ✅ implemented |
| `nimo run <plan.json> [--resume]` | Execute a saved plan through the engine (currently stub generator) | ✅ implemented |

## 4. Plan DSL steps (what the engine can execute)

| Step kind | What it does | Needs model? | Status |
|-----------|--------------|--------------|--------|
| `skGenerate` | Produce prose via the model (the only "thinking" step) | yes | ✅ |
| `skExtract` | Pull a focused slice from a source (model or memory lookup) | sometimes | ✅ |
| `skSummarize` | Condense input to essence | yes | ✅ |
| `skValidate` | Deterministic gate: word count, paragraph count, repeating segments | no | ✅ |
| `skWrite` | Deterministic file output | no | ✅ |
| `skLoop` | Data-driven fan-out over an extracted list (splices sub-plan per item) | no (loop itself) | ✅ |
| `skReport` | Checkpoint visible to the user | no | ✅ |

## 5. REPL / chat commands (the unified DSL, RFC 2111)

### Turn control
| Verb | What it does | Status |
|------|--------------|--------|
| `/send <text>` | Start a new user turn (idle-only) | ✅ (harness's bare input) |
| `/steer <text>` | Inject a directive at the next action boundary (does NOT interrupt in-flight step) | 📝 RFC 2111 design |
| `/queue <text> [on-action|on-finish]` | Hold until chosen gate opens | 📝 RFC 2111 design |
| `/flush` | Flush queued messages immediately | 📝 RFC 2111 design |

### Planning
| Verb | What it does | Status |
|------|--------------|--------|
| `/plan <goal>` | Agent thinks and produces a plan in the DSL (copyable artifact) | 📝 RFC 2111 design |
| `/run <plan-dsl>` | Run a plan (or pasted plan text) through the same dispatcher | 📝 RFC 2111 design |
| `/planner --dry <goal>` | Deterministic `interpret` without model (offline plan draft) | ✅ in repl |

### Workspace & session
| Verb | What it does | Status |
|------|--------------|--------|
| `/ws status \| list \| new <name> \| switch <path>` | Workspace management | ✅ in repl |
| `/session new [path] \| status` | Session management (load/save JSONL) | ✅ in repl |

### Story pipeline
| Verb | What it does | Status |
|------|--------------|--------|
| `/story chapter validate <file>` | Deterministic quality check (words, paras, repeats) | ✅ in repl |
| `/story chapter write <path> -p <premise> [--skip-validate]` | Generate a chapter (uses skGenerate internally) | ✅ in repl |
| `/story wiki edit <file> -p <directive>` | Update wiki entry (uses skGenerate internally) | ✅ in repl |

### State & GPU
| Verb | What it does | Status |
|------|--------------|--------|
| `/state list \| ingest -p <text> <file> \| load <file>` | Baked-state cache ops | ✅ in repl |
| `/cuda status` | GPU probe | ✅ in repl |

### Meta
| Verb | What it does | Status |
|------|--------------|--------|
| `/save [path]` | Persist session JSONL | ✅ in harness |
| `/quit` | End session | ✅ everywhere |
| `/help` or `?` | List commands | ✅ in repl |

## 6. Jules (SaaS agent wrapper — separate product)

| Command | What it does | Status |
|---------|--------------|--------|
| `nimo jules spawn <repo> "<prompt>" [--pr]` | Create a session + queue it for the Jules API | ✅ implemented |
| `nimo jules queue` | List queued sessions with PR/status | ✅ |
| `nimo jules status <id>` | One session: state + head of activities | ✅ |
| `nimo jules watch [id]` | Poll until completion, showing new activity lines | ✅ |
| `nimo jules activities <id>` | Readable activity stream | ✅ |
| `nimo jules prs` | Pull requests across queued/completed jobs | ✅ |
| `nimo jules sessions` | Recent sessions from the API | ✅ |
| `nimo jules send <id> "<msg>"` | Message the agent | ✅ |
| `nimo jules approve <id>` | Approve a pending plan | ✅ |
| `nimo jules prune [--all]` | Drop done/terminal jobs from the queue | ✅ |

## 7. Backends & GPU policy

| Backend | Where it runs | GPU required? | Status |
|---------|---------------|---------------|--------|
| `cuda` | RTX 2050 (sm_86, 4 GB) | yes | ✅ compiled to `librwkv_cuda.so` |
| `vulkan` | general GPU | optional | ✅ compiled |
| CPU fallback | — | no (stub only) | ❌ intentionally absent |

**Runtime policy (RFC 7500):** `canRunRealModel(cfg)` → if model file exists + a backend lib dlopen's, use real model; else degrade to `[stub]`. No compile-time flags.

## 8. Config knobs (nimo.json, RFC 4000)

| Key | Default | Purpose |
|-----|---------|---------|
| `model` | `models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin` | Model path |
| `vocab` | `rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt` | Vocab path |
| `backend` | `cuda` | cuda or vulkan |
| `lib` | (auto) | Explicit librwkv.so path |
| `gpuLayers` | `-1` (auto-clamp to free VRAM) | Layer offload cap |
| `temperature` | `0.7` | Sampling temp |
| `topP` | `0.7` | Top-p sampling |
| `maxTokens` | `50` | Default token cap |
| `quant` | `""` | Auto-quantize raw→cached (e.g. "Q4_K") |
| `modelCacheDir` | `.nimo/model-cache` | Content-addressed quantized model cache |
| `stateCacheDir` | `.nimo/state-cache` | Baked state cache |
| `systemPrompt` | `"You are nimo."` | Baked into state (RFC 8000) |
| `bakeContext` | `false` | Resume baked state; bake on miss |
| `scriptReplies` | `""` | L1 test seam: JSON array of scripted model replies |
| `seed` | `-1` (clock-seeded) | Fixed seed for reproducible draws |

## 9. Session message types (RFC 1100)

| Type | What it is |
|------|------------|
| `user` | The user's input |
| `think` | Model reasoning (optional, between user and response) |
| `text` | Model's text response |
| `tool_call` | Model's tool invocation (e.g. `[tool] run_pipeline {...}`) |
| `tool_result` | Tool's output |
| `system` | Immutable operational rules (never in the JSONL) |

Flow: `user → (think) → text\|tool_call → tool_result → user → ...`

## 10. Deterministic tests (RFC 9400)

| Test | What it checks | Status |
|------|----------------|--------|
| `nimo unit` (102 checks) | Tool calling, loop termination, session JSONL, workspace, story, memory, jules queue | ✅ green |
| `nimo test` (L0 + L1) | L0: unit suite; L1: CLI integration with scripted model (`--script-replies`) | ✅ 19/19 |
| `state_bake_test` | Bitwise state-bake soundness (checkpoint == continue) | ✅ |
| `smoke_test.sh` | Real-model smoke (CUDA, ~4s per shot) | ✅ |

## 11. Model evals (RFC 9300)

| Family | What it checks | Status |
|--------|----------------|--------|
| Planner compilation (offline) | 5 fixed prompts → plan step count > 0 | ✅ deterministic |
| Scored state_bake (online) | Judge-bake → produce sample → judge scores 0-10 per metric per scenario | ✅ with ~40-80% unparsed rate (2.9B model limitation) |

## 12. Speculative research (RFC 9500+ — NOT shipped)

These are deliberately wild design directions, not features:
- 9500 Living Worlds
- 9510 Time-Travel Debugging for Plans
- 9520 Dream Compiler
- 9530 Agent Biomes
- 9540 Narrative Physics
- 9550 Memory Ecology
- 9560 Ontological Git
- 9570 Blackboard Cities
- 9580 Counterfactual Labs
- 9590 Adversarial Muse
- 9600 Midnight Shift
- 9610 Simulation Forges
- 9620 Skill Genomes
- 9630 Plurality Court
- 9640 Attention Weather
- 9650 Artifact Economy
- 9660 Ritual Interfaces
- 9670 Embodied Workspaces
- 9680 Mythic Observability
- 9690 Consentful Autonomy
- 9710 State Dreaming (evidence-gated continual improvement)

> All marked "speculative research RFC" — must not be represented as implemented.

## 13. What the unified chat (RFC 2111) will unify

The design folds these into one entry:
- `nimo harness` (bare agent loop)
- `nimo repl` (command shell)
- legacy `nimo chat` (deprecated)

One process, two threads (reader + agent), one dispatcher. All above verbs accessible. Plan DSL ≡ command DSL.
