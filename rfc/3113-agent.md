# Agent Pipeline

Autonomous agent actions pipeline.

## Concept

An agent performs actions on behalf of the user. It can do autonomous actions.

## Pipeline Structure

```
User intent
  → Agent analyzes intent
  → Agent plans steps (may generate pipeline.nim)
  → Agent executes steps
  → Agent returns results
  → Agent takes follow-up actions (if needed)
```

## Example: Autonomous Research

```nim
# Agent researches a topic autonomously
let topic = generate("Research the following: quantum computing basics", target = "research/topic.md")

# Agent breaks into sub-topics (parallel)
let qubits = generate("Explain qubits", target = "research/qubits.md")
let entanglement = generate("Explain entanglement", target = "research/entanglement.md")
let applications = generate("List applications", target = "research/applications.md")

# Agent synthesizes
let summary = summarize(
  """
  Qubits: #{qubits}
  Entanglement: #{entanglement}
  Applications: #{applications}
  """,
  length = "brief",
  target = "research/summary.md"
)
```

## Agent Capabilities

- Intent parsing
- Task decomposition
- Pipeline generation
- Error recovery (retry/abort)
- User notification on completion

## See Also

- [9000-agent.md](9000-agent.md) — agent concept
- [3000-pipeline.md](3000-pipeline.md) — core DSL
- [2000-cli.md](2000-cli.md) — intent extraction flow
