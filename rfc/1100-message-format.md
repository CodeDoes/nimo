# 1100 — Message Format

Raw text format for each content type, and the **planner's emission format**.
**Status: partial — parsing lives in `src/harness.nim`; its role is shifting from
"the model improvising tool calls in chat" to "the planner emitting a plan".**

## Text

```
Hi there! How can I help?
```

## Thinking

```
Assistant:
I should respond politely.
Hi there! How can I help?
```

## Planner emission format

The **planner state** emits a parseable plan. Its text form reuses the step
types below; the parser (reusing `parseToolCalls` in `src/harness.nim`) compiles
a stream of these into a **plan** (see [3500-plan-format.md](3500-plan-format.md)).
The same step may appear multiple times in sequence — a *plan*, not a one-shot
call.

### 1. `[step]` line (preferred)

```
[step] extract {"source": "outline", "for": "characters"}
[step] generate {"skill": "chapterState", "context": "outline:ch3, wiki:ch3"}
[step] validate {"minWords": 500, "minParagraphs": 5}
[step] report {"title": "story finished"}
```

### 2. `<tool_call>` JSON tag

```
<tool_call>[{"name": "extract", "arguments": {...}},
           {"name": "generate", "arguments": {...}}]</tool_call>
```

### 3. Bare JSON object lines (fallback — small RWKV models emit these)

```json
{"name": "extract", "arguments": {"source": "outline", "for": "ch3"}}
{"step": "generate", "skill": "chapterState", "context": "..."}
{"arguments": {"source": "outline", "for": "characters"}}    // implied extract
```

An unrecognized non-JSON line is dropped (the plan must be pure structure); the
output text itself is produced by `Generate` steps, not by the planner.

> Note: the old chat-tool semantics ("model improvises `[tool] run_pipeline` in
> its reply") are superseded. The format survives as the *planner emission
> format*; the executor drives the steps, and the model no longer decides tools
> mid-reply.

## Tool Result

```
User: <tool_result>[nimo] ▶ 1/10 ... ✔ 1/10 ...</tool_result>

Assistant:
```

## Plan and Report — in the tree

Not player-emitted free text; they are recorded as messages in the history
(see [1000-session.md](1000-session.md) "One turn").

- `plan` — the compiled program (the planner emits structure only; see
  [3500-plan-format.md](3500-plan-format.md)). One `plan` node per turn, whose
  children are the step executions.
- `report` — the assistant's prose about the run, carrying a `kind`:
  `planner` (before executing), `step` (after one step), `finished` (the
  turn's answer). A report is plain text.

## See Also

- [1000-session.md](1000-session.md) — session data model + turn lifecycle
- [3500-plan-format.md](3500-plan-format.md) — the plan these emit