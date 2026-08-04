# 3000 — Pipeline

The `run_pipeline` tool. **Status: implemented** in `src/pipeline.nim`.

## What it is

`run_pipeline` is the one tool the harness gives the model. When the model
wants to "write", "generate", or "produce content", it calls this tool with an
intent, and the pipeline module turns that intent into a small set of steps
that run through the model.

## How it works (step by step)

### 1. The model emits a tool call

The model outputs a line like:

```
[tool] run_pipeline {"intent": "write a poem about roses"}
```

The harness parses this (3 formats accepted — see
[1100-message-format.md](1100-message-format.md)) and calls
`pipelineTool(session, arguments)`.

### 2. Parse the intent

The arguments JSON is read. If it isn't valid JSON, the tool returns an error
string. Otherwise the `intent` field is extracted (fallback: `"unknown task"`).

### 3. Create a pipeline

A `Pipeline` object is created with a unique id
(`pipe_<timestamp>`), a timestamp, and status `running`.

### 4. Add and run steps

The MVP runs one step per call:

- `generateStep(name, prompt, target)` — asks the model to produce content for
  the intent, writes the reply to `target` (default `output.txt`), marks the
  step completed.

Two more step helpers exist for longer pipelines:

- `summarizeStep(name, input, length)` — asks the model to summarize input
  (brief/medium/detailed).
- `extractStep(name, input, filter)` — asks the model to pull out specific
  facts from input.

Each step: added as `pending` → started (`running`) → completed with output (or
failed with an error message).

### 5. Finish and report

The pipeline status becomes `completed`. A JSON report is saved to
`<cwd>/.nimo/<pipeline-id>.json` with the id, status, timestamp, and every step
(id, name, status, output). The tool returns a short confirmation string which
the harness feeds back to the model as the tool result.

## The whole flow

```
model: [tool] run_pipeline {"intent": "write a poem about roses"}
  → parse intent
  → new pipeline (running)
  → generateStep: model writes the poem → output.txt
  → pipeline completed
  → save .nimo/<id>.json
  → tool result: "[nimo] Pipeline <id> completed with 1 steps"
model: (reads the result) → answers the user in natural text
```

## Config interaction

Steps use the generation defaults from config (`temperature`, `topP`, and the
session's max tokens) — see [4000-config.md](4000-config.md).

## See Also

- [3400-agent.md](3400-agent.md) — the loop that executes this tool
- [1100-message-format.md](1100-message-format.md) — tool-call text forms
- [1000-session.md](1000-session.md) — how tool calls/results become messages
