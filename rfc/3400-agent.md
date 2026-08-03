# 3400 — Agent Pipeline

Agent performs autonomous actions on behalf of user.

## Concept

Agent receives a goal, decomposes it into steps, executes, and reports back.

## Flow

```
User: "Research quantum computing basics"

Agent:
  1. Parse intent
  2. Create pipeline:
     - Research topic
     - Break into sub-topics
     - Generate summary
  3. Execute pipeline
  4. Return results
```

## Example Pipeline

```nim
# Agent researches autonomously
let topic = generate("Research: quantum computing basics", target = "research/topic.md")

# Parallel sub-topics
let qubits = generate("Explain qubits", target = "research/qubits.md")
let entangle = generate("Explain entanglement", target = "research/entanglement.md")
let apps = generate("List applications", target = "research/apps.md")

# Synthesize
let summary = summarize(
  "Qubits: $#{qubits}\nEntanglement: $#{entangle}\nApps: $#{apps}",
  length = "brief",
  target = "research/summary.md"
)
```

## Agent Capabilities

- Intent parsing
- Task decomposition
- Pipeline generation
- Error recovery (retry/abort)
- Progress notification

## Harness loop (implemented in src/harness.nim)

The harness drives the agent loop over a real model:

```
user -> generateTurn -> parseToolCalls(reply)
  if no calls  -> final text answer, stop
  else         -> for each call: addToolCall -> executeTool -> addToolResult;
                    feed results back, generate again
```

- **Termination guard**: max 8 iterations (`MaxToolIterations`); if the model
  keeps calling tools past that, the turn is marked `aborted = true`.
- **Tool results** are appended with `Now answer the user's question with
  natural text` so the model closes the loop.
- `run_pipeline` consumes one generation step internally, so evals budget 2
  responses per iteration.

## See Also

- [2000-cli.md](2000-cli.md) — intent extraction
- [3000-pipeline.md](3000-pipeline.md) — pipeline DSL
- [1100-message-format.md](1100-message-format.md) — tool-call parse forms
- [9300-eval.md](9300-eval.md) — tool/loop evals
