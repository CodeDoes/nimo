# 8000 — State Bake

Pre-compute model state from a context so later sessions resume instantly.
**Status: implemented** in `src/state_cache.nim` and `src/rwkv/state/cache.nim`.

## Why

Evaluating the system prompt every run is wasted work. Baking runs it once,
saves the resulting model state to disk, and later runs load the state directly
— the model starts already "knowing" the context.

## How baking works (step by step)

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
