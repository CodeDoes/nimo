# 3000 — Pipeline

Interactive pipeline tool. User can interact at different stages.

## Flow

```
user -> pipeline -> root.chat
user -> pipeline -> pipeline.relavent-story.relavent-chapter.write
pipeline.report -> user
user -> pipeline -> pipeline.story.summarize
pipeline.report -> user
...
```

## Example Session

```
messages[0] (user): "Write a cyberpunk story about Max"
messages[1] (tool_call): "run_pipeline: write story"
messages[2] (tool_result): "[nimo] ▶ 1/10 Generating wiki: Max...
                            [nimo] ✔ 1/10 (0.8s)
                            ...
                            [nimo] ✔ 10/10 (45.2s)"
messages[3] (user): "Now write chapter 3"
messages[4] (tool_call): "run_pipeline: write chapter 3"
messages[5] (tool_result): "[nimo] ▶ 1/3 Writing chapter 3...
                            [nimo] ✔ 1/3 (12.4s)
                            → chapters/03.md"
messages[6] (user): "Summarize the story so far"
messages[7] (tool_call): "run_pipeline: summarize"
messages[8] (tool_result): "[nimo] ▶ 1/1 Summarizing...
                            [nimo] ✔ 1/1 (3.2s)
                            → summary.md"
```

## Pipeline Structure

```
pipeline.relavent-story.relavent-chapter.write
pipeline.story.summarize
pipeline.report
```

Nested paths for organized workflow.

## Workspace Artifacts

```
~/.ws/myproject/
  wiki/
    max.md
  chapters/
    01.md
    02.md
    03.md
  summary.md
```

## Interrupt / Resume

Ctrl+C saves state:
```
~/.ws/myproject/.nimo/pipeline_{id}.json
```

Resume:
```
nimo resume {pipeline_id}
```

## See Also

- [1000-session.md](1000-session.md) — session data model
- [9100-logging.md](9100-logging.md) — JSONL logging
- [9200-trace.md](9200-trace.md) — trace output
- [3200-story.md](3200-story.md) — story pipeline example
