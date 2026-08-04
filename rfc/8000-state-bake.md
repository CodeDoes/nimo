# 8000 — State Bake

Bake a context into model state so later sessions resume instantly, and **bake skills** — the state-tuning mechanism. **Status: implemented** in `src/state_cache.nim` / `src/rwkv/state/cache.nim` (context bake); the **skill** extension (`bake planner` / `bake output`) is planned.

## Two jobs of bake

Bake has two distinct uses, both cheap (no gradients) — this is the
**state-tuning** idea: what big models get from expensive fine-tuning, a small
model gets from baked states.

| Bake | Job | Output | Status |
|------|-----|--------|--------|
| **Context** | pre-compute the fixed system context once, resume fast | a state vector | ✅ implemented |
| **Skill (planner)** | make the model emit structured plans from fuzzy goals | a state vector that <br>yields parseable plans | planned |
| **Skill (output)** | make the model produce a certain *sort* of prose | a state vector that <br>yields e.g. chapters/wikis | planned |

A **skill** is a self-contained bundle (zip-like):

```nim
Skill:
  name: string
  bakedState: bytes      # the .state.bin — the "tuning"
  template: string       # the pattern it resumes
  example: string        # the demonstration it was baked from
```

## How baking works (step by step)

## Context bake (mechanisms)

### The cache key

A state is cached by a hash of three things (`stateCacheKey`):

1. **Model file signature** — size + mtime + first 512 bytes
2. **Vocab file hash** — the vocab text hashed
3. **Context text** — the exact prompt/context string

Any change (different model, different vocab, different prompt) → different key
→ fresh bake.

### The file layout

`<cacheDir>/<first-12-hex-of-key>.state.bin` — a raw little-endian float32
vector. The size must exactly match the model's `stateLen`; a mismatch means
"treat as a miss".

### Bake on miss, resume on hit

`bakeContext(model, tok, modelPath, vocabPath, context)`:

1. Compute the key and look for the cached file.
2. Found → load it and return (fast path).
3. Not found → tokenize the context, evaluate it through the model once,
   save the state to the cache path, return it.

`resumeFromCache(...)` is the strict variant: only loads if already cached,
never bakes.

## Where it's used

- The harness seeds the model from a baked state when `bakeContext` is on and a
  `systemPrompt` is configured (`session_manager.initModel`).
- `context_state_cache.nim` wraps this and the model cache together, tracking
  hit/miss stats (`nimo eval` covers the cache logic).
- The `bake` CLI writes a state file directly from a prompt.

## Example

```bash
# one-off: bake a prompt into a state file
nimo bake "User: hi\n\nBot: Hello!" baked_state.bin

# chat can load that file directly
nimo chat model.bin vocab.txt baked_state.bin
```

## See Also

- [8150-quantization.md](8150-quantization.md) — the model cache it pairs with
- [4000-config.md](4000-config.md) — `systemPrompt`, `bakeContext`, `stateCacheDir`
- [docs/architecture.md](../docs/architecture.md) — state-tuning as a principle
- [1100-message-format.md](1100-message-format.md) — planner emission format
