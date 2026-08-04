# Plan: Make src/ follow the plan/engine intent

## Status: NOT STARTED

Design is formalized in `rfc/3500-plan-format.md` + `rfc/3600-engine.md`
(commit `7271b86`). This plan evaluates the current code and lays out the
migration. Each phase is a commit and must leave `nimo eval` green.

## Code evaluation — what contradicts the intent today

| File | Today | Contradiction |
|------|-------|---------------|
| `session.nim` | `generateTurn` buffers the whole reply, returns it | **Streaming** (RFC 3600) |
| `session_manager.nim` | same buffered `generateTurn` (duplicated) | **Streaming**; also duplicate session type with `session.nim` |
| `chat.nim` | `let reply = s.generateTurn(...); echo "Bot: ", reply` | **Streaming** — waits for the full reply |
| `harness.nim` | `runHarnessTurn`: model improvises `[tool]` calls in reply, re-parses ≤8× | **Planner→plan→engine** (RFC 3400) — the improvisation loop |
| `pipeline.nim` | `pipelineTool` = one generate step, dormant summarize/extract helpers | **Real pointed steps** (RFC 3000) |
| `story.nim` | hardcoded `for ch in 1..N`, buffered, no character extraction | **Plan template** (RFC 3200) |
| `nimo.nim` | `story` subcommands are echo placeholders | **Wire story** (RFC 2000) |
| `bake_state.nim` | bakes a context prompt only | **Skill bakes** (RFC 8000) |
| `memory.nim`/`fiaas.nim` | exist, not wired into generation | **`lookupMemory` pointed tool** |
| `session_manager.nim` | message tree only; no plan/checkpoints | **Record plan + checkpoints** (RFC 1000) |
| `evals.nim` | tests the improvisation tool loop | **Test the plan flow** (RFC 9300) |

**What already matches**: `generate.nim` streams per token (`stdout.write` +
`flushFile` — the canonical example); `workspace.nim` artifact dirs;
`validateChapter`/`critiqueChapter`/`countWords`/`countLines`;
`parseToolCalls`/`stripToolCallText` (re-scope as the planner parser);
`memory.nim`/`fiaas.nim` (pointed tool material).

## Target structure (new modules)

```
src/program.nim       # Step variants + Plan (id, goal, cursor, steps, status)
                      #   serialize/load JSON, advance, splice, checkpoint
src/engine.nim        # run(plan, session, TokenSink) — the infinite loop;
                      #   interrupt (signal); save/restore checkpoint
src/orchestrator.nim  # interpret(userMsg) -> Plan — template registry first,
                      #   learned planner-state later
src/skills/           # baked skill bundles (planner + output states)
```

## Phase 1 — Streaming foundation

**Files**: `session.nim`, `session_manager.nim`, `chat.nim`, `harness.nim`
(just the generation call sites), `pipeline.nim`, `story.nim`.

1. Add `type TokenSink* = proc(text: string)` in `session.nim` (exported).
2. Add `generateTurnStream*(s, prompt, sink, temp, topP, maxTokens)` in
   `session.nim`: same loop as `generateTurn` but calls `sink(tokenStr)` per
   token. Keep `generateTurn` as a thin wrapper (collect into a string) so
   callers/evals don't break.
3. Same change in `session_manager.nim` (its online `generateTurn`), and route
   through a shared helper if practical.
4. `chat.nim`: `s.generateTurnStream(line, proc(t) = stdout.write(t))` +
   flush — the user literally sees every token.
5. `harness.nim`/`pipeline.nim`/`story.nim` generation call sites: pass sinks
   (progress/echo) once Phase 3/4 reshape them.

**Done when**: chat streams token-by-token; generate unchanged; `nimo eval` 34/34.
**Commit.**

## Phase 2 — program.nim + engine.nim (the runtime)

**New files**: `src/program.nim`, `src/engine.nim`.

1. `program.nim`:
   - `Step` variants: `Extract(source, filter, for)`, `Summarize(input, length)`,
     `Generate(skill, context)`, `Validate(text)`, `Write(path, content)`,
     `Loop(items, buildSubPlan)`, `Report(title)`.
   - `Plan` = `id, goal, cursor, steps, status` + `save(path)` (compact JSON,
     one line) + `load(path)` + `advance()` + `splice(steps, at)` +
     `checkpoint()`.
   - Works in `-d:harnessOffline` (no model import).
2. `engine.nim`:
   - `run(plan, session, sink)`: the loop — advance → execute step →
     checkpoint; `Loop` splices sub-steps from the extracted list; `Generate`
     streams through the sink; `Validate` gates; `Report` emits `▶/✔` events.
   - `interrupt`: a `volatile bool` checked between steps and between tokens
     (signal handler or keypress), snapshot + return control.
   - `resume(planPath)`: reload plan + cursor + state and continue.
3. Evals (extend `evals.nim`): plan save/load round-trip, cursor advance,
   splice, engine step execution with `genStub`, checkpoint/resume.
   Update `rfc/9300-eval.md` count if it changes.

**Done when**: new evals pass; offline build compiles.
**Commit.**

## Phase 3 — Orchestrator: replace the improvisation loop

**Files**: `harness.nim`, `session_manager.nim`, `evals.nim`, new
`src/orchestrator.nim`.

1. `orchestrator.nim`:
   - `interpret(userMsg, session, config) -> Plan`: deterministic **template
     registry** first (matches goal keywords → story / memory / answer / custom
     templates from `nimo.json`), each template a `Plan` of pointed steps.
   - Learned planner-state path (stub now): a `planner` skill bake emits
     `[step]`/JSON lines (RFC 1100 emission format); parse via the re-scoped
     `parseToolCalls` → build the plan. This is the distillation target.
2. `harness.nim`: replace `runHarnessTurn` with
   `interpret → engine.run → report`:
   - Delete the ≤8-iteration improvisation loop.
   - `parseToolCalls`/`stripToolCallText` re-scoped to *planner output parsing*
     (accept `[step] name {...}` + the JSON forms); used by the orchestrator.
   - Keep `MaxToolIterations` as the engine's max-steps guard (a plan that
     never terminates aborts — the evals already test this shape).
3. `session_manager.nim`: session records the plan + checkpoints (new message
   kinds or a session-level plan field), so `/save` shows the run.
4. `evals.nim`: rework `evalToolCalling`/`evalLoopTermination` to the new flow:
   - tool-calling eval → planner emission parse → plan compilation.
   - loop-termination eval → engine max-steps abort.
   - session-logging eval → user → steps → results → answer chain still holds.

**Done when**: harness runs planner→plan→engine; evals green (count updated).
**Commit.**

## Phase 4 — Story + pipeline as plan templates

**Files**: `story.nim`, `pipeline.nim`, `nimo.nim` (story wiring), `workspace.nim`.

1. `story.nim`: expose the RFC 3200 template as a `Plan`:
   `outline → extract characters → per-character wiki → per-chapter
   (extract outline slice + wiki slice → generate) → validate → critique →
   write`. `validateChapter`/`critiqueChapter`/`summarizeChapter`/
   `generateWikiEntry` become the pointed tools behind the steps.
   Generation streams through the engine.
2. `pipeline.nim`: `pipelineTool` = build a plan from the intent (template
   registry) + engine-run it; keep the JSON manifest (now the plan artifact in
   `.nimo/programs/<id>.json`). Delete the single-step MVP.
3. `nimo.nim`: wire `story generate/validate/critique/outline` to the real
   functions (they are currently echo placeholders) — `story generate` runs the
   template through the engine with streaming.
4. `workspace.nim`: add `.nimo/programs/` to created workspaces (plans live
   with the project).

**Done when**: `nimo story generate <premise>` streams a real chapter with
validation; pipeline manifests are plans; evals green.
**Commit.**

## Phase 5 — Skill bakes + memory pointed tool

**Files**: `bake_state.nim`, `memory.nim`, `fiaas.nim`, `orchestrator.nim`.

1. `bake_state.nim`: two skill modes:
   - `bake planner <examples-file>` → a skill whose output parses as a plan
     (RFC 1100 emission format).
   - `bake output <examples-file> <template>` → an output-state for a *sort* of
     prose (chapter/wiki/outline/critique...).
   - Bundle format: state + template + example, one self-describing file.
2. `memory.nim`/`fiaas.nim`: expose `lookupMemory(query, workspace)` as a
   pointed tool; `Extract(source="memory", ...)` steps use it
   (`getRelevantContext`).
3. `orchestrator.nim`: wire the planner-skill path (learned planner) behind the
   template registry — the distillation target from frontier traces.

**Done when**: bake writes skills; memory lookup works as a plan step; offline
evals green.
**Commit.**

## Phase 6 — CLI surface + docs alignment

**Files**: `nimo.nim`, `cli.nim`, `docs/*`, `analysis/status.md`.

1. `nimo plan <goal>` — compile to a plan (show the steps, save to
   `.nimo/programs/`).
2. `nimo run <plan> [--resume]` — execute with streaming.
3. `harness` = the engine chat (Phase 3 result).
4. Update `docs/how-it-works.md` / `getting-started.md` / `status.md` to the
   planner→plan→engine model and streaming; docs already carry
   `docs/architecture.md`.

**Done when**: `nimo eval` green; docs describe the real code.
**Commit.**

## Risks / notes

- **Evals coupling**: the harness rewrite touches exactly what `evals.nim`
  tests (tool loop, session logging). Update evals in the same commit as the
  harness change; keep the count truthful in `rfc/9300-eval.md`.
- **Two Session types** (`session.nim` object vs `session_manager.nim` ref):
  don't unify in this pass — just give both a streaming variant. Unification
  is a separate cleanup.
- **Learned planner is a bake**: the template registry ships first
  (deterministic, no model), so the system works before the skill bakes exist;
  the planner state is the swap-in later (distillation target).
- **Interrupt on GPU**: token loop must check the interrupt flag between
  `eval` calls so Ctrl-C behaves mid-generation without corrupting state.

## See also

- `rfc/3500-plan-format.md`, `rfc/3600-engine.md` — the specs
- `docs/architecture.md` — the design principles
- `plan/0014-engine-design.md` — where the formalization started