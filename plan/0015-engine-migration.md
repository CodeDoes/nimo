# Plan: Make src/ follow the plan/engine intent

## Status: IN PROGRESS

Done:
- [x] Phase 0 step 1: rename evals -> unit (a409844)
- [x] Phase 2: program.nim + engine.nim + validate.nim runtime, unit suite
  34 -> 58 checks (1005670); unit tests caught 2 real latent bugs
  (validate.countWords never assigned its result -> always 0;
  repeating-segment check never fired)
  CORRECTION: the earlier claim that story.nim's countWords had the same bug
  is WRONG — story.nim's version has `return count` and is correct; only
  validate.nim was broken. story.nim still carries a private duplicate
  countWords/countLines that Phase 4 should point at validate.nim instead.
- [x] Phase 0 item 1 (one Session type): deleted src/session.nim; all of
  generate/chat/nimwave_app/bake_state use session_manager.Session via
  newSession()+initModel() (380b29c). One generateTurn now.
- [x] Phase 0 item 6 (rename suite): evals.nim -> unit.nim, `nimo unit` (a409844).

Remaining Phase 0 items:
- [x] one shared bootstrapSession(cfg) in src/bootstrap.nim
- [x] CLI delegates to libraries (nimo.nim inline workspace/story -> modules)
- [x] decompose runHarnessTurn into recordTurnStart/parseReply/runCalls/
      buildNextContext (unit suite now tests the primitives; harness.nim
      main() stops re-dispatching generate/bake via execCmd)
      + restored NIMO_SMOKE single-shot mode (smoke_test.sh path)
      + fixed workspace.nim unexpanded-tilde bug (workspaces were created
      under a literal ./~ in the cwd)

(Row removed above: the session-nim vs session_manager duplication is resolved —
session_manager.Session is the single canonical type.)

Note: Phase 2 was pulled ahead of the remaining Phase 0 items deliberately —
its work is fully offline/unit-verifiable, which matches "unit tests first".
The session unification is NOT online-only: it is verified by (1) offline
compile of every affected binary, (2) offline unit tests on session
bookkeeping, (3) the smoke test for the token loop. Interactive chat is not
needed to verify a structural refactor.

Design is formalized in `rfc/3500-plan-format.md` + `rfc/3600-engine.md`
(commit `7271b86`). This plan evaluates the current code and lays out the
migration. Each phase is a commit and must keep the unit suite green.

> **Phase 0 first**: the *architecture* above the model layer lacks clean
> abstraction/composition — two `Session` types, triplicated bootstrap, CLI/dispatcher
> monoliths. Migrations must NOT build on top of that. Phase 0 unifies the session
> abstraction and shares bootstrap (behavior-identical, unit-green), so Phase 2/3
> build on clean primitives. (`rwkv.nim` itself is already well-abstracted.)

## Guiding principles (the "why" behind every phase)

These are the non-negotiable criteria each phase is checked against.

### A. Unit tests vs Model evals — two separate things

- **Unit tests** (today `src/unit.nim`, `nimo unit`): verify OUR deterministic
  machinery — parser, caches, GPU policy, loop bookkeeping. Offline, scripted,
  must always be green. **Renamed to `nimo unit`** so the word is precise.
- **Model evals** (planned, `nimo model-eval`): probe the **black-box model** in
  a controlled environment to check whether our assumptions about its
  mechanisms are accurate. The model cannot be changed; we only run it and
  observe. Probabilistic — report **rates over N fixed-seed trials**, not hard
  pass/fail.

The design rests on beliefs about the model; model evals are the only way to
falsify them. Belief + the probe that tests it:

| Belief | Probe (rate over N trials) |
|--------|---------------------------|
| resumes a pattern forever | long single-mode run; measure pattern-held / drift |
| a baked state encodes a "sort of output" that generalizes | bake an output-state; generate on an unrelated topic; measure if the shape/quality carries over |
| planner emits parseable structure, not prose | varied goals → parse → % valid plans of expected step types |
| mixes/forgets heterogeneous content → "one kind at a time" | focused slice vs mixed blob; measure mixing/forgetting on each |

Model evals are also the **distillation feedback loop**: a distilled planner
passes only when its output parses as a valid plan at an acceptable rate.

### B. Behavior over internals

A test is *behavioral* when it asserts the **contract / observable outcome** and
survives re-wiring of *how* it's done. It tests *internals* when it records the
machinery and breaks when that machinery changes (today's `turn.iterations
== 2`-style asserts are internals tests). Unit tests and model evals both
assert outcomes at the contract level. We achieve this by giving every
capability a public interface (see D), so there is a contract to test against.

### C. Top-level interface ≤ 6 concepts

The whole codebase must be explainable by holding these in your head:

```
Session             — the one thing you talk to (messages + model + state)
Plan                — a list of Steps; the unit of work (data: resumable)
Step                — Extract / Generate / Validate / Write / Loop / Report
Engine.run          — the one loop: advance → execute → stream → checkpoint
bootstrapSession(cfg) — how you get a Session
Pointed tools       — extract / summarize / lookupMemory / ... (each a Step)
```

Every phase keeps this to ≤6 terms. Violations to avoid: two things named
"Session"; "dispatcher" meaning two things; CLI containing business logic;
entry points that don't all go through the same bootstrap + engine.

### D. Capability ⇒ interface (no capabilities reachable only via internals)

Any capability that should be usable must be reachable through a public Step /
public command — never only through its implementation. Today `memory.nim` /
`story.nim` / `pipeline.nim` violate this (implemented but no top-level
interface). The rule: make the capability a pointed tool or a plan template;
then it is both usable and testable as behavior. If a capability isn't meant
to be public, make it private.

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
| `unit.nim` | tests the improvisation tool loop | **Test the plan flow** (RFC 9300) |

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

## Phase 0 — Architecture refactor: one Session, shared bootstrap (PREREQUISITE)

> Why before the engine work: the codebase currently has **two parallel "Session"
> abstractions** (`session.nim` object + `session_manager.nim` ref), **triplicated
> model bootstrap** across `harness`/`chat`/`generate` `main()`, and **monolithic
> CLI/dispatcher/harness procs**. The engine and orchestrator must be composed
> from clean, single primitives — not from two worlds held together by
> duplication. `rwkv.nim` is already well-abstracted; the surgery is above it.

**Files**: `session.nim`, `session_manager.nim`, `bootstrap.nim` (new),
`harness.nim`, `chat.nim`, `generate.nim`, `nimo.nim`, `workspace.nim`, `unit.nim`.

1. **One `Session` type.** Make `session_manager.Session` (ref, with
   messages/tools/**and** model/state) the single canonical session. Either:
   - fold the low-level fields in cleanly, or
   - define an explicit `SessionModel` trait/record that both provide, so
     `sampleReply` (below) and every tool accept **one** session type.
   `generate.nim`/`chat.nim` move onto that type; `session.nim` keeps only the
   raw model/state helpers (`initRwkvModel`, `newState`, `loadState`, …). No
   two near-identical `generateTurn` procs anymore.
2. **One shared token loop**: `sampleReply(s, prompt, temp, topP, maxTokens,
   sink) -> string` in one place; both `session` and `session_manager`
   generation use it. Per-token `sink` is the seam Phase 1 turns fully
   streaming. (This subsumes the old `sampleReply` in the plan.)
3. **One shared bootstrap**: new `src/bootstrap.nim` with
   `bootstrapSession(cfg, opts) -> Session` — bind backend → GPU policy →
   quant cache → init model → seed — used by `harness`, `chat`, `generate`.
4. **CLI delegates to libraries.** `nimo.nim` stops embedding workspace/story
   logic inline and calls `workspace.nim`/`story.nim` functions. `harness.nim`'s
   `main()` stops re-dispatching generate/bake/chat; every binary owns only its
   own arg parse + `bootstrapSession` + run loop.
5. **Decompose `runHarnessTurn`** into composed procs (`recordTurnStart`,
   `parseReply`, `runCalls`, `buildNextContext`) — see original plan text below.
6. **Rename the unit suite**: `src/evals.nim` / `nimo eval` → **`nimo unit`**
   (guiding principle A: the word "eval" belongs to model-behavior probes).
   Update `rfc/9300-eval.md` (becomes "unit tests") and any references.
7. **Unit tests follow the code**: update imports to the single `Session`, push
   tests onto the composed primitives. `check()` helper optional; count stays
   truthful.

**Done when**: exactly one session type (or one explicit interface); one
`sampleReply`, one `bootstrapSession`; `nimo unit` green (34/34 or
count-updated); harness/chat/generate spot-checked live.
**Commit.**

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

**Done when**: chat streams token-by-token; generate unchanged; `nimo unit` green.
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
3. Unit tests (parts 1-2 already landed): plan save/load round-trip, cursor
   advance, splice, engine step execution with the mock GenerateFn,
   checkpoint/resume.
   Update `rfc/9300-eval.md` count if it changes.

**Done when**: new unit tests pass; offline build compiles.
**Commit.**

## Phase 3 — Orchestrator: replace the improvisation loop

**Files**: `harness.nim`, `session_manager.nim`, `unit.nim`, new
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
3. `session_manager.nim`: the history is the single record (RFC 1000).
   Session writes `plan` nodes (steps + checkpoint cursor), `workspace`/`model`
   events (bound when generation starts, again on every switch), and
   per-message `bakeRef` (which baked skill state produced each generated
   message). The header is `id` + `timestamp` only; the current intent is the
   latest user message (sessions have many). Resume reads the latest plan node
   cursor + latest model/workspace events.
4. `unit.nim`: rework `evalToolCalling`/`evalLoopTermination` to the new flow:
   - tool-calling eval → planner emission parse → plan compilation.
   - loop-termination eval → engine max-steps abort.
   - session-logging eval → user → steps → results → answer chain still holds.

**Done when**: harness runs planner→plan→engine; unit suite green (count updated).
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
validation; pipeline manifests are plans; unit suite green.
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
unit suite green.
**Commit.**

## Phase 6 — CLI surface + docs alignment

**Files**: `nimo.nim`, `cli.nim`, `docs/*`, `analysis/status.md`.

1. `nimo plan <goal>` — compile to a plan (show the steps, save to
   `.nimo/programs/`).
2. `nimo run <plan> [--resume]` — execute with streaming.
3. Goal-first surface (RFC 2000): `nimo new <goal>` opens a session
   (bootstrap + compile + run); `nimo list/open/continue` manage sessions;
   `story`/`chat`/`harness` nouns are dropped from the everyday surface.
   `nimo story ...` becomes reachable only through goals, never as a verb.
3. `harness` = the engine chat (Phase 3 result).
4. Update `docs/how-it-works.md` / `getting-started.md` / `status.md` to the
   planner→plan→engine model and streaming; docs already carry
   `docs/architecture.md`.

**Done when**: `nimo unit` green; docs describe the real code.
**Commit.**

## Phase 7 — Model eval harness (black-box probes)

**Files**: `src/model_evals.nim` (new), `nimo.nim`, `rfc/9700-model-eval.md` (new).

1. `nimo model-eval` + `src/model_evals.nim`: controlled probes of the **real
   model** (black box — we can't change it, we only observe). Deterministic
   conditions: fixed seeds, fixed prompt sets, fixed metrics, raw outputs saved
   to `.nimo/model-evals/`. Reports **rates over N trials**, not pass/fail:
   - planner emission: N goals → % that parse as valid plans
   - output-state generalization: bake a state → generate on unrelated topics →
     measure whether the "sort" carries over (the falsifiable state-tuning bet)
   - one-kind-at-a-time: focused slice vs mixed blob → mixing/forgetting rate
   - pattern-resume: long single-mode run → drift over tokens
2. Gate for learned pieces: the distilled planner (Phase 5) ships only when its
   emission rate clears the bar. Model evals are the distillation feedback loop.
3. Unlike the unit suite (offline, deterministic), model evals need the model
   and GPU/backend — they run separately: `nimo unit` vs `nimo model-eval`.

**Done when**: `nimo model-eval` runs on the real backend, prints rates, saves
artifacts; `nimo unit` unaffected.
**Commit.**

## Risks / notes

- **Unit-test coupling**: the harness rewrite touches exactly what `unit.nim`
  tests (tool loop, session logging). Update unit tests in the same commit as
  the harness change; keep the count truthful. Phase 0's decomposition makes
  this a behavior test, not an implementation test.
- **Two Session types**: the crux of the composition problem. Phase 0 unifies
  them (or defines one explicit interface both provide) BEFORE anything else;
  the engine cannot be composed from two worlds. This is the highest-risk,
  highest-value refactor — do it with the unit suite green throughout.
- **Streaming rides the refactor**: once `sampleReply` lives in one place
  (Phase 0 item 2), Phase 1 adds the sink there and everywhere is streaming.
- **Learned planner is a bake**: the template registry ships first
  (deterministic, no model), so the system works before the skill bakes exist;
  the planner state is the swap-in later (distillation target).
- **Interrupt on GPU**: the token loop must check the interrupt flag between
  `eval` calls so Ctrl-C behaves mid-generation without corrupting state.

## See also

- `rfc/3500-plan-format.md`, `rfc/3600-engine.md` — the specs
- `docs/architecture.md` — the design principles
- `plan/0014-engine-design.md` — where the formalization started