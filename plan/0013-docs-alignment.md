# Plan: Docs Alignment with Code

## Status: COMPLETE ✓

## Goal

Make `rfc/`, `docs/`, and `analysis/` describe the **actual code** — plain
language, step-by-step logic for each part, no outdated "desired structure".

## What was done

### analysis/
- `status.md` rewritten: module map of all 30+ `src/` modules, each with a
  "how it works" column; 6 request flows (generate, harness turn, story,
  memory, quantization, state baking); honest known gaps.

### docs/ (new end-user guides)
- `index.md` — overview, command table, project layout
- `getting-started.md` — install, model, first commands
- `how-it-works.md` — full request flow: settings → backend → caches → model →
  generation → harness loop → pipeline tool
- `story-writing.md` — outline → chapters → validate → critique → revision
- `memory.md` — FIAAS vectors + cosine search + MemoryStore step by step

### rfc/ (24 files)
- All RFCs now carry an implementation status (✅ / partial)
- Core RFCs rewritten to match code exactly:
  - 1000 session (message model as coded in `session_manager.nim`)
  - 2000 CLI (real commands + step-by-step flows)
  - 3000 pipeline (actual `run_pipeline` tool)
  - 3200 story (validation rules as coded)
  - 3400 agent (8-iteration guard)
  - 4000 config (real keys; removed non-existent personas)
  - 6000 src (actual layout)
  - 7500 GPU (corrected: no CPU fallback in code)
  - 8000 / 8150 caches (as coded)
  - 9300 eval (the 34 actual checks)

## Verification

- `git log`: 3 commits (`da754d9` analysis, `9cf7a3f` docs, `80cb24a` rfc)
- `nimo eval`: 34/34 still passing (docs only, no code change)
- Working tree clean; ready to push

## See Also

- [analysis/status.md](../analysis/status.md) — the code-aligned status map
- [docs/index.md](../docs/index.md) — end-user entry point
