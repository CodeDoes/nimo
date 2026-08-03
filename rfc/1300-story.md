# 1300 — Story

Creative writing workflow. High context preservation, memory retrieval, longer outputs.

## Config

```toml
[workload.story]
temperature = 0.8
top_p = 0.95
max_tokens = 2000
context_pruning = "minimal"  # preserve global context
tool_integration = "memory"  # read/write files, retrieve context
```

## Flow

```
user intent → pipeline → wiki generation → chapter writing → summary → next chapter
```

## Example Session

```jsonl
{"type":"session","version":3,"id":"...","cwd":"/home/kit/dev/nimo","workload":"story"}
{"type":"message","id":"msg1","role":"user","content":[{"type":"text","text":"Write a cyberpunk story about Max"}]}
{"type":"message","id":"msg2","role":"assistant","content":[{"type":"thinking","thinking":"I should create a pipeline to generate this story."},{"type":"toolCall","id":"call1","name":"run_pipeline","arguments":{"intent":"Write a cyberpunk story about Max"}}],"stopReason":"toolUse"}
{"type":"message","id":"msg3","role":"toolResult","toolCallId":"call1","content":[{"type":"text","text":"[nimo] ▶ 1/10 Generating wiki: Max...\n[nimo] ✔ 1/10 (0.8s)\n...\n[nimo] ✔ 10/10 (45.2s)"}],"isError":false}
{"type":"message","id":"msg4","role":"assistant","content":[{"type":"text","text":"Your story is ready! Check wiki/max.md and chapters/01.md"}]}
```

## Memory System

- **Wiki**: Character/world entries stored in `wiki/`
- **Context Buffers**: Extracted key details from wiki
- **Chapter Summaries**: Brief recaps for continuity
- **Outline**: Plot structure for long-term planning

## Pipeline Steps

```
1. Generate wiki entries (parallel)
2. Extract context buffers
3. Write Chapter 1 (with wiki context)
4. Summarize Chapter 1
5. Write Chapter 2 (with recap + partner context)
6. ...
7. Finalize outline
```

## Interruption

User can interrupt mid-story and adjust:
```
User: "Actually, make Max more stoic"
→ Pipeline resumes with updated character profile
```

## See Also

- [0001-vision.md](0001-vision.md) — workload contexts
- [3000-pipeline.md](3000-pipeline.md) — pipeline execution
- [3200-story.md](3200-story.md) — story pipeline example
