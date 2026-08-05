# NIMO Engine (plan/engine intent)

The NIMO engine is the core framework that manages and executes complex, multi-step tasks. It operates on a robust, stateful pipeline that guarantees tasks are thoughtfully planned, sequentially executed, and accurately reported.

## Core Flow

The engine operates via a four-stage pipeline:

1. **Intent**: The engine captures the overarching goal or specific user request. This defines what needs to be achieved.
2. **Plan**: Based on the intent, the engine breaks the task down into discrete, manageable steps.
3. **Execute**: The engine sequentially processes each planned step.
4. **Report**: After execution, the engine compiles the results and presents a summary or the final output.

## Step Types

During the `Execute` phase, the engine can utilize various step types to accomplish its goals. These steps represent the foundational actions the model can take:

- **Extract**: Pull specific facts, data, or context from the provided text or workspace.
- **Summarize**: Condense large amounts of information into a concise format.
- **Generate**: Create new content (like prose, code, or ideas) based on the current context and prompt.
- **Validate**: Check the generated output against specific rules, facts, or instructions to ensure accuracy.
- **Write**: Save the final, validated output to the file system (e.g., writing a story chapter to disk).

## Session Persistence (JSONL)

To maintain state and allow for long-running or interrupted tasks, the engine persists sessions using a **JSONL (JSON Lines)** format.

- **Append-only log**: Each turn (user input, model response, tool call, or internal state change) is appended as a new JSON object on a new line in the session file.
- **Message-tree format**: This structured logging captures the complete history and context, ensuring that the engine has a perfect record of the ongoing task.
- **Location**: These files are typically stored in the workspace's `sessions/` directory.

## Resuming a Session

Because every action is logged to the JSONL file, resuming a session is straightforward:

1. The engine reads the JSONL file line by line.
2. It rebuilds the context window and the internal state up to the exact point the session was paused or interrupted.
3. It determines the next required action based on the reconstructed state (e.g., executing the next step in the `Plan` or asking the user for input).

This allows you to stop a long-running pipeline and seamlessly continue it later without losing progress or context.
