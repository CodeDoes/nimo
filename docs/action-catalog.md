# nimo — Complete Action & Concept Catalog

## Legend
- ✅ Implemented
- 📝 Designed (RFC)
- 🔧 In progress
- ❌ Removed / superseded
- 🤔 Undecided / pending

---

## 1. Core Generation Primitives

| Action | Status | Notes |
|--------|--------|-------|
| `structured <Schema> "<prompt>"` | 📝 | **NEW DSL primitive** — generate + parse + bind to variable |
| `generate "<prompt>"` | ✅ | Legacy direct generation (harness bare input) |
| `prose "<prompt>"` | 🤔 | Alias for generate? Or distinct? |
| `extract "<filter>" from "<source>"` | ✅ | Engine step skExtract (also: memory lookup) |
| `summarize "<input>" [--length]` | ✅ | Engine step skSummarize |
| `convert <from> to <to>` | 🤔 | Generic transduction (prose↔data, data↔prose) |

## 2. Variable & State Operations

| Action | Status | Notes |
|--------|--------|-------|
| `set <var> = <expr>` | 📝 | Variable assignment |
| `get <var>` | 📝 | Variable read |
| `<var> = ...` | 📝 | Implicit set (Nim-style) |
| `load "<path>"` | ✅ | Read file into variable |
| `save "<path>", <var>` | ✅ | Write variable to file |
| `memory "<text>"` | ✅ | Store in memory store |
| `recall "<query>"` | ✅ | Lookup from memory |

## 3. Control Flow

| Action | Status | Notes |
|--------|--------|-------|
| `for <item> in <list>: ...` | ✅ | Engine step skLoop |
| `while <cond>: ...` | 🤔 | Loop until condition |
| `if <check>: ... else: ...` | ✅ | Conditional execution |
| `try: ... except: ...` | 🤔 | Error handling |
| `break` | 🤔 | Exit loop |
| `continue` | 🤔 | Skip to next iteration |

## 4. Validation & Quality

| Action | Status | Notes |
|--------|--------|-------|
| `validate <text>` | ✅ | Deterministic gate (words/paras/repeats) |
| `judge <text> [--metric]` | ✅ | Model-as-judge scoring (0-10) |
| `check <var>, <schema>` | 📝 | Schema validation |
| `critique <text>` | ✅ | Story critique (strengths/weaknesses) |

## 5. File & Document Operations

| Action | Status | Notes |
|--------|--------|-------|
| `write "<path>", <content>` | ✅ | Engine step skWrite |
| `read "<path>"` | ✅ | Load file |
| `edit "<path>" [--directive]` | 🤔 | Edit existing file |
| `append "<path>", <text>` | 🤔 | Append to file |
| `delete "<path>"` | 🤔 | Remove file |
| `list ["<dir>"]` | 🤔 | List files |

## 6. Plan & Pipeline

| Action | Status | Notes |
|--------|--------|-------|
| `plan "<goal>"` | ✅ | Agent produces plan in DSL |
| `run "<plan>"` | ✅ | Execute plan |
| `plan.dry "<goal>"` | ✅ | Offline deterministic plan draft |
| `pipeline "<intent>" [target]` | ✅ | Legacy run_pipeline tool |
| `step "<kind>" ...` | 🤔 | Execute single step type |

## 7. Session & Conversation

| Action | Status | Notes |
|--------|--------|-------|
| `send "<text>"` | ✅ | New user turn |
| `steer "<text>"` | 📝 | Inject at next boundary |
| `queue "<text>" [gate]` | 📝 | Hold with delivery trigger |
| `flush` | 📝 | Flush queue |
| `save [path]` | ✅ | Persist session JSONL |
| `resume "<path>"` | ✅ | Load existing session |
| `quit` | ✅ | End session |

## 8. Workspace & Organization

| Action | Status | Notes |
|--------|--------|-------|
| `ws.new "<name>"` | ✅ | Create workspace |
| `ws.switch "<path>"` | ✅ | Change active workspace |
| `ws.list` | ✅ | List workspaces |
| `ws.status` | ✅ | Show current workspace |
| `ws.remove "<name>"` | ✅ | Delete workspace |

## 9. Story Pipeline

| Action | Status | Notes |
|--------|--------|-------|
| `outline "<premise>"` | ✅ | Generate story outline |
| `character "<name>"` | ✅ | Generate/lookup character |
| `wiki "<path>" --edit "<directive>"` | ✅ | Wiki entry generation |
| `chapter "<path>" -p "<premise>"` | ✅ | Chapter generation |
| `chapter.validate "<file>"` | ✅ | Quality check |
| `chapter.critique "<file>"` | ✅ | Generate critique |

## 10. Data Types & Entities

| Action | Status | Notes |
|--------|--------|-------|
| `item` | 🤔 | Generic data item |
| `location` | 🤔 | Geographic/place entity |
| `event` | 🤔 | Temporal occurrence |
| `timeline` | 🤔 | Sequence of events |
| `note` | 🤔 | Free-form text capture |

## 11. Model & Backend

| Action | Status | Notes |
|--------|--------|-------|
| `cuda status` | ✅ | GPU probe |
| `bake "<model>" "<prompt>"` | ✅ | State baking |
| `quantize "<in>" "<format>" "<out>"` | ✅ | Model quantization |
| `doctor` | ✅ | Health check |

## 12. Jules (SaaS)

| Action | Status | Notes |
|--------|--------|-------|
| `jules spawn "<repo>" "<prompt>"` | ✅ | Create agent session |
| `jules queue` | ✅ | List queued sessions |
| `jules status "<id>"` | ✅ | Session status |
| `jules watch [id]` | ✅ | Poll for completion |
| `jules send "<id>" "<msg>"` | ✅ | Message agent |
| `jules approve "<id>"` | ✅ | Approve plan |
| `jules prune [--all]` | ✅ | Clean queue |

## 13. Eval & Test

| Action | Status | Notes |
|--------|--------|-------|
| `unit` | ✅ | 102 offline checks |
| `model-eval` | ✅ | Planner compilation evals |
| `model-eval --scored` | ✅ | Model-as-judge scored evals |
| `state_bake_test` | ✅ | State soundness checks |

---

## Summary

| Category | Count |
|----------|-------|
| ✅ Implemented | ~45 |
| 📝 Designed (RFC) | ~15 |
| 🔧 In progress | 0 |
| ❌ Removed/superseded | ~5 |
| 🤔 Undecided | ~15 |

### Key Gaps (Undecided)
- `convert` — generic transduction primitive?
- `prose` — distinct from `generate`?
- `edit` — file editing verb?
- `while` — loop variant?
- `set`/`get` — explicit variable ops vs implicit?
- Data entities (`item`, `location`, `event`, `timeline`) — schema types or just plan steps?
