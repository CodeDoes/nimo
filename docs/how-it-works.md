# How It Works — Step by Step

This page explains what happens inside NIMO when you run a command. It's
deliberately non-technical: each numbered step is one logical piece.

## The command layer

`nimo` is a thin dispatcher. It reads the first word of your command and hands
off to the right piece:

1. `nimo generate ...` → runs the generator binary
2. `nimo quantize ...` → runs the quantizer binary
3. `nimo chat ...` → runs the chat binary
4. `nimo harness ...` → runs the agent loop
5. `nimo bake ...` → runs the state baker
6. `nimo workspace ...` → handled directly (create/list/use/status/remove)
7. `nimo story ...` → handled directly (generate/validate/critique/outline)
8. `nimo unit` → runs the offline test suite

## Settings: defaults → file → environment

Every tool needs settings (model path, backend, temperature, cache folders).

1. Start with the built-in defaults (CUDA backend, Q4_K model path, temp 0.7).
2. If `nimo.json` exists in the working directory, its keys override defaults.
3. Environment variables (`NIMO_MODEL`, `NIMO_BACKEND`, ...) override the file.

Highest priority wins. This is why the same binary behaves differently in
different folders.

## Choosing a backend (before the model loads)

The model runs on CUDA (NVIDIA GPU) or Vulkan. The choice happens in one
place (`selectBackend`):

1. If a `lib` path is set in config, use exactly that library.
2. Else if a `backend` was set (config file or `--backend` flag), use it.
3. Else use the compile-time default (CUDA).

For CUDA specifically, NIMO probes the GPU *first* via the NVIDIA driver
(`cuInit` + `cuDeviceGetCount`). Three outcomes:

- **OK** — one or more usable devices → proceed with GPU layers.
- **Unusable** — driver present but no device (often "GPU requires reset") →
  print the diagnosis and the fix, then stop (no silent crash).
- **Unknown** — no NVIDIA driver found → same clean refusal.

Vulkan skips the probe (it doesn't depend on the NVIDIA driver).

## Loading the model (with caches)

Loading a multi-GB model is the slow part, so there are two caches:

**Model cache** (`raw → quantize → cache`):

1. Read the model header. If the file is already quantized, use it as-is.
2. Otherwise compute a quick signature (file size + modified time + first 512
   bytes).
3. Look in `.nimo/model-cache/` for a file named after that signature.
4. Found → load the cached copy (skip quantization entirely).
5. Not found → quantize the raw model into the cache once, then use it.

**State cache** (`context → bake → cache`):

1. Key = hash of (model signature, vocab file, context text).
2. If a baked state file exists for that key, load it — the model starts
   already "knowing" the context without re-reading it.
3. Otherwise run the context through the model once and save the state.

Both caches make repeated runs much faster.

## Generation: prompt → tokens → text

For `generate` (and inside chat/harness) the same core loop runs:

1. Encode the prompt text into tokens (numbers the model understands).
2. Feed the tokens through the model in chunks (16 at a time).
3. The model outputs probabilities for the next token.
4. Sample one token (temperature 0.7, top-p 0.7 by default).
5. Append it to the reply, feed it back, repeat.
6. Stop when the stop token appears, or the max length is reached.
7. Report how fast it was (e.g. `200 ms/token`).

## The harness loop (tool calling)

`harness` is the "agent" mode:

1. Wrap your message with a system prompt that explains the `run_pipeline` tool.
2. Ask the model for a reply.
3. Look at the reply for a tool call. Three formats are recognized:
   - **Bracket format** (the primary one):
     ```
     [tool] run_pipeline {"intent": "write a poem"}
     ```
   - **XML format**:
     ```xml
     <tool_call>{"name": "run_pipeline", "arguments": {"intent": "write a poem"}}</tool_call>
     ```
   - **Bare JSON format**:
     ```json
     {"name": "run_pipeline", "arguments": {"intent": "write a poem"}}
     ```
4. **No tool call** → the reply is the final answer. Done.
5. **Tool call found** → record the call, run the tool, record the result,
   then feed the result back to the model and ask it to continue.
6. Repeat up to 8 iterations; if the model keeps calling tools forever, the
   turn is marked aborted instead of looping endlessly.

### Session JSONL message-tree format

The whole conversation is saved as JSONL: one line for the session header, one
line per message, each with an id and parent id forming a tree. This allows branching conversations. Each message links back to the previous one via a `parentId` chain. It also includes a `stopReason` indicating how the generation completed (e.g. `stop`, `length`, `tool_call`).

## The `run_pipeline` tool

When the model calls `run_pipeline`, the pipeline module:

1. Parses the intent from the arguments (e.g. "write a poem about roses").
2. Creates a pipeline object with a running status.
3. Adds steps — the MVP does one "generate" step:
   - `generateStep` → asks the model to write the content → writes it to
     `output.txt`.
4. Marks the pipeline completed.
5. Saves a pipeline report JSON into `./.nimo/<pipeline-id>.json`.

`summarizeStep` and `extractStep` exist for longer pipelines: summarize input
into bullets, or pull out specific facts with a filter.

## Sessions and reports

- **Sessions** hold the message tree and can be saved to a file (`/save`).
- **Reports** turn a session, workspace, or story into a readable markdown
  summary with metadata, saved as JSON.

## Where everything lives

- Workspaces: `~/.ws/<name>/` with `wiki/ chapters/ sessions/ .nimo/`.
- App folder: `./.nimo/` with `state/ cache/ logs/ sessions/ pipelines/`.
- Caches: `.nimo/model-cache/` (quantized models) and `.nimo/state-cache/`
  (baked states).
