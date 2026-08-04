# 3500 — Plan Format

The plan is the core artifact: it's what the planner emits and what the
executor runs. Because the plan is **data** (not prose), it is resumable,
interruptible, observable, and safe to edit. This RFC defines the step
vocabulary and the plan shape. **Status: design reference** (the runtime is
built against this).

## Design goals

- Machine-parseable (a bad planner emits something the parser rejects).
- Mostly **flat** — pointed tools are the workhorses; deep nesting is rare.
- **Data-driven** — loops fan out over lists produced by earlier steps.
- **Resumable** — save plan + cursor (+ state) to continue from step N.

## Step vocabulary

```nim
type Step =
  | Extract(source, filter, for)   # pull the relevant slice (model or memory lookup)
  | Summarize(input, length)       # condense to essence
  | Generate(skill, context)       # the ONLY "thinking" step: uses an output-state
  | Validate(text)                 # deterministic gate (words, paragraphs, repeats)
  | Write(path, content)           # deterministic file output
  | Loop(items, buildSubPlan)      # data-driven: splice a sub-plan per item
  | Report(title)                  # checkpoint visible to the user
```

A plan is a **list** of steps plus metadata:

```nim
Plan:
  id: string
  goal: string          # the compiled intent (human-readable)
  cursor: int           # resume point
  steps: seq[Step]
  status: Running | Paused | Done | Interrupted
```

## Notes on each step

- **Extract** is the most important tool. Most tasks decompose by slicing
  *information* rather than splitting the *goal*. Examples:
  - "extract the characters from the outline"
  - "extract the outline events relevant to character Kael"
  - "extract the outline segment for chapter 3"
- **Generate** is the only step where the model produces original prose. It
  always runs **on a focused slice** (one kind of thing) through an output-state
  — never on the whole outline + whole wiki at once.
- **Validate** never uses the model — it is pure math (word count, paragraph
  count, repeating segments), so it is fast and deterministic.
- **Loop** turns an extracted list into a fan-out. The list comes from
  execution; the sub-plan is spliced into the plan as steps appear.
- **Report** is a checkpoint — it shows the user progress at a step boundary,
  never a "waiting wall" (tokens stream through Generate either way).

## Example: a story plan

```nim
Plan(goal = "write a story")

  1. Generate(outlineState,   premise)             # → outline.md
  2. Report("outline ready")

  3. Extract(outline, "the characters")            # → characters[]
  4. Loop(characters):
        events = Extract(outline, for: c)
        Generate(wikiState, from: events)          # → wiki/{c}.md

  5. Loop(outline.chapters):
        beat   = Extract(outline, for: ch)
        wslice = Extract(wiki,    for: ch's cast)
        Generate(chapterState, from: beat + wslice)   # → chapters/{ch}.md

  6. Report("story finished")
```

Note: no sub-planner is needed. Every hard part collapses into
"extract the right slice, then do one focused thing." The only structure beyond
a flat list is the `Loop` fan-out.

## The planner's job (learned, distilled)

The planner — a baked *planner state* — needs to answer one small question
repeatedly and emit a flat, parseable list:

> *"Given this goal, what sequence of extract / summarize / generate steps
> (with what filters) do I run?"*

It does not invent hierarchies and never writes prose. Distillation from
frontier traces teaches exactly this skill.

## See also

- `rfc/3600-engine.md` — the executor that walks this plan
- `docs/architecture.md` — the design principles behind this format