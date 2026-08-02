## What is this file for?

RFC for the pipeline DSL — a structured, DAG-based narrative generation system.

## Concept

A domain-specific language for defining multi-step LLM generation pipelines where:
- **Atomic wiki generation** runs in parallel (independent nodes)
- **Targeted extraction** filters raw output into focused context buffers
- **Narrative generation** depends on prior context (DAG edges)
- **Convergence** assembles final outputs from intermediate results

## DSL Syntax

```nim
pipeline "Story Title":

  # Step 1: Parallel atomic generation
  max_wiki = generate(
    "Generate character entry for Max: robot ninja, stealth specialist.",
    target = "wiki/max.md"
  )

  rob_wiki = generate(
    "Generate character entry for Rob: heavy ordnance tactical partner.",
    target = "wiki/rob.md"
  )

  # Step 2: Context extraction (in-memory filtering)
  max_ctx = extract(max_wiki, "Max's combat abilities, gear, and personality")
  rob_ctx = extract(rob_wiki, "Rob's equipment, tactics, and background")

  # Step 3: Dependent generation (DAG: max_ctx + city_wiki → ch1)
  ch1 = generate(
    """
    World Setting:
    ${city_wiki}

    Protagonist Profile:
    ${max_ctx}

    Task: Write Chapter 1 introducing Max operating solo.
    """,
    target = "chapters/01.md"
  )

  # Step 4: Transformation (summarize for downstream consumption)
  ch1_recap = summarize(ch1, length = "bullet_points")

  # Step 5: Branching (parallel, both depend on ch1_recap)
  ch2 = generate(
    """
    Previous Narrative State:
    ${ch1_recap}

    Partner Profile:
    ${rob_ctx}

    Task: Write Chapter 2 introducing Rob as Max's partner.
    """,
    target = "chapters/02.md"
  )

  draft_outline = generate(
    """
    Current Progress:
    ${ch1_recap}

    Main Antagonist Profile:
    ${boss_wiki}

    Task: Draft escalation plot beats.
    """,
    target = "draft_outline.md"
  )

  # Step 6: Convergence
  ch3 = generate("...", target = "chapters/03.md")
  final_outline = generate("...", target = "outline.md")
```

## Execution Model

```
Phase 1 (Parallel):  wiki generation (max, rob, boss, city)
Phase 2 (Sequential): extract → build context buffers
Phase 3 (DAG):       ch1 depends on max_ctx + city_wiki
Phase 4 (Parallel):  ch2 + draft_outline both depend on ch1_recap
Phase 5 (Sequential): ch3 → final_outline
```

Key properties:
- **Topological sort** determines execution order
- **Independent nodes** run concurrently
- **Context references** (`${var}`) are resolved from prior artifact outputs
- **Targets** are written to disk; intermediate values stay in-memory

## Node Types

| Node | Purpose | I/O |
|------|---------|-----|
| `generate(prompt, target)` | Call LLM, write to file | prompt → file |
| `extract(src, filter)` | Filter source output to focused context | source → string |
| `summarize(src, length)` | Condense for downstream consumption | source → short string |

## Why This Matters

The current CLI (`nimo chat`) handles linear, interactive chat. This DSL enables:
- **Multi-step creative workflows** (wiki → chapters → outline)
- **Context precision** (only feed relevant excerpts, not full documents)
- **Parallelism** (independent wiki entries generated concurrently)
- **Reproducibility** (same pipeline = same structure, different outputs)

## Open Questions

- Should the DSL be a `.nimo` file or embedded in the CLI?
- How do we handle long context windows? (chunking? RAG?)
- Should there be a visual DAG editor?
- Error handling: what happens if one node fails? Retry? Skip?
