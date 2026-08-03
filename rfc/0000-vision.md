# NIMO — Product Vision

## What is NIMO?

A CLI tool for running RWKV-7 language models locally. It supports:

- **Chat** — interactive conversation with the model
- **Generate** — one-shot text generation
- **Bake** — pre-compute model state for fast resume
- **Dashboard** — full-screen TUI with conversation history
- **Pipeline** — multi-step LLM workflows driven by natural language intent

## Core Concept: Pipelines

Instead of a single prompt-response loop, NIMO lets users express complex tasks as **pipelines**.

Example:
```
User: "Write a cyberpunk story about a robot ninja named Max"

NIMO response:
[nimo] Creating plan...
[nimo] Plan:
  1. Generate wiki: Max
  2. Generate wiki: Rob
  3. Extract context
  4. Write Chapter 1
  5. Write Chapter 2
  ...

[nimo] ▶ 1/10 Generating wiki: Max...
→ wiki/max.md

[nimo] ✔ 1/10 (0.8s)
[nimo] ▶ 2/10...
```

The user describes what they want in natural language. NIMO parses it into a pipeline, then executes each step, showing progress inline.

## Workspace Model

Each project lives in a workspace directory:
```
~/.ws/myproject/
  ├── config.toml       # model path, personas, settings
  ├── wiki/             # character/world entries
  ├── chapters/         # generated story chapters
  └── outline.md        # story outline
```

Two modes:
- **Release** — defaults to current working directory
- **Dev** — defaults to last workspace used

## Tool Calling

The model can call tools. When it does, NIMO intercepts the call and runs the appropriate handler.

```
User: What's the weather in Boston?

Assistant: 
[get_weather {"location": "Boston, MA"}]

User: <tool_result>72°F, sunny</tool_result>

Assistant: The weather in Boston is 72°F and sunny.
```

## Think Blocks

The model can "think" before responding. This is hidden from the user unless they enable debug mode.

```
Assistant: 
<model is thinking...>
Hi there! How can I help?
```

## Status

- ✅ Core inference engine (rwkv.nim, tokenizer, sampling)
- ✅ Session management (session.nim)
- ✅ 5 CLI binaries (chat, generate, bake, dashboard, main)
- ❌ Pipeline DSL execution
- ❌ Tool calling parsing
- ❌ Think block parsing
- ❌ Workspace management
- ❌ Intent-to-DSL extraction
