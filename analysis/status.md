# NIMO — Implementation Status

This file maps the **actual code** in `src/` to what each part does, and how the
pieces fit together. It replaces the old "desired structure" notes — everything
below exists and runs today.

## Module Map (src/)

| Module | Purpose | How it works (step by step) |
|--------|---------|------------------------------|
| `nimo.nim` | Unified CLI entry | Reads the first argument (generate / quantize / harness / chat / bake / workspace / story / eval), then either spawns the matching binary from `build/` or runs the logic inline (workspace + story). |
| `config.nim` | Settings | Starts from built-in defaults, reads `nimo.json` if present, then applies `NIMO_*` env vars on top. Holds model path, vocab, backend, temperature, cache dirs, system prompt. |
| `rwkv.nim` | Backend dispatcher | The single place that picks which `librwkv.so` to load. `selectBackend(cfg)` decides (config file > runtime flags > compile-time default), `bindBackend(path)` opens the library and wires every `rwkv_*` C function into Nim. |
| `gpu.nim` | GPU health probe | Before loading the model, it calls into the NVIDIA driver (`libcuda.so.1`) directly: `cuInit` + `cuDeviceGetCount`. Reports OK / unusable / unknown so a broken GPU gives a clear message instead of a crash. |
| `generate.nim` | One-shot text generation | Parse args → pick backend → bind library → load model → encode the prompt → run it through the model in chunks → sample one token at a time until the stop token or max length → print speed (ms/token). |
| `quantize.nim` | Model quantization | Read the 24-byte GGML header, make sure the input is raw FP16/FP32, load the backend, call the quantizer, report the size reduction. |
| `chat.nim` | Interactive chat | Load model, seed a greeting, then loop: read a line from the user → generate a reply → print it. Supports `/reset` and `/quit`. |
| `session.nim` | Low-level inference session | Wraps the loaded model, tokenizer, state vector, logits and RNG. `generateTurn` is the core: encode the message, evaluate the prompt, sample tokens, stop cleanly. |
| `bake_state.nim` | State baking | Takes a prompt (or file), encodes it, runs it through the model once, and writes the resulting model state to a binary file. |
| `harness.nim` | Agent loop | The brain. Builds a system prompt + user message, calls the model, looks for tool calls, executes them, feeds results back, repeats (max 8 iterations), then gives the final answer. |
| `session_manager.nim` | Message model | Stores the conversation as a JSONL message tree: user messages, assistant text, tool calls, tool results — each with an id and parent id. Also holds the tool registry and saves sessions to disk. |
| `pipeline.nim` | `run_pipeline` tool | The one tool the harness offers. Creates a pipeline, adds steps (generate / summarize / extract), runs each via the model, writes outputs to files, saves a pipeline JSON report into `.nimo/`. |
| `workspace.nim` | Project folders | Creates a workspace at `~/.ws/<name>/` with `wiki/`, `chapters/`, `sessions/`, `.nimo/` (with `model-cache/` and `state-cache/`), plus a `config.toml` and `outline.md`. Lists, loads, finds, removes workspaces. Writes wiki entries and chapter files. |
| `story.nim` | Story pipeline | Generates an outline, then chapters one by one. Each chapter is validated (word count ≥ 500, paragraphs ≥ 5, no repeating 3-word segments). Failed chapters get one critique + revision attempt, then are saved to the workspace. |
| `session_branch.nim` | Conversation branches | Lets a session fork into alternative paths: create a branch from a parent message, switch between branches, save/load branch metadata as JSON. |
| `fiaas.nim` | Vector memory store | The "Fictional AI Associative Storage": each text gets a fixed-size pseudo-random vector (hash-based, deterministic), and search ranks entries by cosine similarity. Entries are saved/loaded as JSON. |
| `memory.nim` | Memory layer on top of FIAAS | Adds memories, searches them, remembers characters by name, and builds a short "relevant context" block to inject into prompts. |
| `report.nim` | Reports | Builds session / workspace / story reports as markdown text with metadata, saves/loads them as JSON, formats them for display. |
| `system_instructions.nim` | Workload prompts | Stores named instruction sets (chat / story / pipeline). `getInstruction(workload)` returns the highest-priority matching instruction, defaulting to a sensible fallback. |
| `model_cache.nim` | Quantized model cache | Content-addressed cache: given a raw model, computes a fast signature (size + mtime + first 512 bytes), and reuses (or produces) the quantized copy instead of re-quantizing every run. |
| `state_cache.nim` | Baked state cache | Keyed by (model signature, vocab hash, context hash). On first use it "bakes" the context into a state file; later runs load the state directly and skip the prompt evaluation. |
| `context_state_cache.nim` | Combined cache | Wraps the state cache and model cache together and tracks hit/miss stats so you can see how often the caches actually save work. |
| `nimo_folder.nim` | `.nimo/` folder | Creates the standard app folder with `state/`, `cache/`, `logs/`, `sessions/`, `pipelines/` and a `config.json`. Provides path helpers for each sub-folder. |
| `unit.nim` | Test suite | 61 offline checks (no model needed): tool-call parsing, loop termination, JSONL session shape, cache logic, chapter validation, memory search, and more. Run with `nimo unit`. |

## How the pieces flow

### One-shot generation

```
user runs `nimo generate --backend cuda --model X --prompt "Hi"`
  -> nimo.nim spawns build/generate
  -> config.nim resolves settings (file + env)
  -> rwkv.nim selectBackend() picks the CUDA backend lib
  -> bindBackend() dlopens librwkv.so and wires the C API
  -> session.nim loads the model + tokenizer
  -> prompt is tokenized and evaluated in chunks
  -> sampling loop: token by token until stop / max length
  -> prints the text and the ms/token speed
```

### Harness turn (agent loop)

```
user types a message
  -> session_manager records it as a message
  -> harness builds: system prompt + user message
  -> model generates a reply
  -> harness parses the reply for tool calls (3 forms: [tool], <tool_call>, bare JSON)
  -> no tool call?  -> that reply is the final answer, done
  -> tool call?     -> record it, run the tool (run_pipeline), record the result
                       -> feed result back into the context, ask model to continue
                       -> repeat (up to 8 iterations)
  -> session saved as JSONL (header + messages with parent ids)
```

### Story pipeline

```
`nimo story generate <premise>`
  -> story.nim generateOutline() -> saves outline.md in the workspace
  -> for each chapter (1..N):
       generateChapter() with wiki context + previous recap
       validateChapter() -> word count, paragraphs, repeating segments
       if it fails: critiqueChapter() -> list issues -> one revision attempt
       save chapter to workspace chapters/ (e.g. 01_my_title.md)
```

### Memory

```
any tool or module can store a memory:
  -> memory.addMemory(text, category) -> fiaas.addEntry()
  -> addEntry turns the text into a deterministic vector and stores it
when the story/chat needs context:
  -> memory.getRelevantContext(currentText)
  -> fiaas.search() ranks all entries by cosine similarity to the query
  -> top matches are returned as a short context block
```

## What is NOT implemented (known gaps)

| Gap | Notes |
|-----|-------|
| Real embeddings | FIAAS uses hash-based pseudo-vectors, not a real embedding model. Good enough for the MVP, documented honestly. |
| Story CLI wiring | `nimo story generate/validate/critique/outline` print placeholders; the real story functions live in `src/story.nim` and are exercised by evals/tests, not yet from the CLI with a live model. |
| Branch merge | `mergeBranch` in `session_branch.nim` is a stub (returns "not yet implemented"). |
| Branch message persistence | `saveBranch`/`loadBranch` store branch metadata (ids, parents, timestamps) but not the messages themselves. |
| `allowCpuFallback` | Mentioned in RFCs; the harness refuses to start on an unusable GPU rather than falling back (GPU-required by default). |
| Server/client/dashboard | No network server; the TUI (`nimwave_app.nim`) is separate from the CLI. |
