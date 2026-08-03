# 8000 — State Bake

Pre-compute model state from a prompt for fast resume.

## Why

Evaluating the system prompt every chat turn is slow. Baking stores the state so we can resume instantly.

## Example

```bash
# Bake state from system prompt
$ nimo bake "User: hi\n\nBot: Hello!" baked_state.bin

# Use baked state
$ nimo chat model.bin vocab.txt baked_state.bin
```

## Cache Key

Hash based on:
- Model file hash
- Vocab file hash
- Prompt content

If any change, cache is invalid and must be re-baked.

## Implementation

Implemented in `src/state_cache.nim` (cache key = model sig + vocab hash +
context; bake-from-Disk, resume-on-miss) and wired into the harness via
`nimo.json` `systemPrompt` + `bakeContext` + `stateCacheDir`. Cache math is
offline-safe and covered by evals.

The companion **model cache** (`src/model_cache.nim`) pre-quantizes raw FP16
models into a content-addressed cache — see [8150-quantization.md](8150-quantization.md).

## See Also

- [2000-cli.md](2000-cli.md) — bake command
- [4000-config.md](4000-config.md) — bake paths in config
