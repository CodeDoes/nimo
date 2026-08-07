# RFC 9902 — Observability Framework

**Status:** design
**Category:** 9 — Infrastructure
**Author:** user + Agnes

## The Goal

Every `generate()` call is observable. Full visibility into:
- Input prompts
- Output responses
- Timing
- Token counts
- Sampling parameters
- Backend used

Reduce verbosity later. For now: **see everything**.

## Why This Matters

1. **Debugging** — when generation fails, you need to see what went in and what came out
2. **Verification** — prove the system works by inspecting each step
3. **Performance** — measure where time is spent
4. **Cost** — track token usage (if applicable)
5. **Reproducibility** — log enough to replay any generation

## Design

### The Hook

Wrap every `generate()` call with observability:

```nim
proc generate*(prompt: string, cfg: GenerateConfig): string =
  let t0 = cpuTime()
  let output = realGenerate(prompt, cfg)
  let elapsed = cpuTime() - t0
  
  # Log everything
  logGenerate(GenerateEvent(
    timestamp: now(),
    prompt: prompt,
    output: output,
    elapsed: elapsed,
    tokens: countTokens(output),
    cfg: cfg
  ))
  
  return output
```

### The Event

```nim
type
  GenerateEvent* = object
    id*: string              # unique ID for correlation
    timestamp*: Time         # when it happened
    prompt*: string          # full input
    output*: string          # full output
    elapsed*: float          # seconds
    tokensIn*: int           # input token count
    tokensOut*: int          # output token count
    cfg*: GenerateConfig     # sampling params, backend, etc.
    schema*: string          # if structured, which schema
    step*: int               # step number in plan
    planId*: string          # plan ID (if in a plan)
```

### The Config

```nim
type
  GenerateConfig* = object
    temperature*: float32
    topP*: float32
    maxTokens*: int
    backend*: string         # "cuda" | "vulkan"
    modelPath*: string
    schema*: string          # for structured()
    skill*: string           # baked state skill
```

### The Logger

```nim
var gLog: File
var gLogOpen = false

proc openGenerateLog() =
  let dir = getCurrentDir() / ".nimo" / "trace"
  createDir(dir)
  let file = dir / "generate-" & nowStr() & ".jsonl"
  if open(gLog, file, fmWrite):
    gLogOpen = true

proc logGenerate*(event: GenerateEvent) =
  if not gLogOpen: return
  let j = newJObject()
  j["id"] = %event.id
  j["timestamp"] = %(event.timestamp)
  j["prompt"] = %(event.prompt)
  j["output"] = %(event.output)
  j["elapsed"] = %(event.elapsed)
  j["tokensIn"] = %(event.tokensIn)
  j["tokensOut"] = %(event.tokensOut)
  j["temperature"] = %(event.cfg.temperature)
  j["topP"] = %(event.cfg.topP)
  j["maxTokens"] = %(event.cfg.maxTokens)
  j["backend"] = %(event.cfg.backend)
  j["schema"] = %(event.schema)
  j["step"] = %(event.step)
  j["planId"] = %(event.planId)
  gLog.writeLine($j)
```

### JSONL Output

Every generate call becomes one JSON line:

```json
{
  "id": "gen_001",
  "timestamp": "2024-01-15T10:30:00Z",
  "prompt": "write a haiku about AI",
  "output": "{\"lines\": [\"bits of light\", \"thinking in silicon\", \"quiet minds\"], \"wordCount\": 5}",
  "elapsed": 1.234,
  "tokensIn": 8,
  "tokensOut": 12,
  "temperature": 0.7,
  "topP": 0.7,
  "maxTokens": 50,
  "backend": "cuda",
  "schema": "Haiku",
  "step": 0,
  "planId": "plan_20240115103000"
}
```

## Integration Points

### 1. Engine (`src/engine.nim`)

Wrap every `produce()` call:

```nim
proc produce(prompt: string): string =
  let event = GenerateEvent(
    id: genId(),
    timestamp: now(),
    prompt: prompt,
    cfg: currentConfig,
    step: p.cursor,
    planId: p.id
  )
  
  let output = realGenerate(prompt, currentConfig)
  
  event.output = output
  event.tokensOut = countTokens(output)
  event.elapsed = cpuTime() - event.timestamp
  
  logGenerate(event)
  
  return output
```

### 2. Structured (`src/chat.nim` or new module)

Wrap `structured()` calls:

```nim
proc structured*(schema: string, prompt: string): JsonNode =
  let output = generate(prompt, cfg)
  let parsed = parseSchema(schema, output)
  return parsed
```

The observability is already captured in the engine wrapper.

### 3. Interactive Chat

Show live trace in terminal:

```
nimo> /run
▶ generate [step 0]
  prompt: "write a haiku about AI"
  output: {"lines": ["bits of light", ...]}
  elapsed: 1.2s
  tokens: 8 in, 12 out
▶ save
  wrote 47 bytes -> haiku.md
▶ done
```

## Trace Files

Location: `.nimo/trace/generate-<timestamp>.jsonl`

One JSON object per line. Append on each run.

## Verification

To prove the system works:

```bash
# Run a simple plan
nimo> /plan "write a haiku"
nimo> /run

# Check the trace
cat .nimo/trace/generate-*.jsonl

# Should see:
# - The prompt
# - The output
# - Timing
# - Token counts
```

## Future: Reduce Verbosity

Once we prove it works, we can:
- Hide full prompt/output (show summaries)
- Aggregate timing
- Filter by schema
- Compact JSON format

But for now: **show everything**.

## Questions

1. **Where does the trace live?** `.nimo/trace/`? Separate dir?
2. **How do we correlate events?** Plan ID + step number?
3. **Do we log in real-time or batch?** Real-time is simpler.
4. **Should we have a trace viewer?** CLI tool to read JSONL?

## Next Steps

1. Implement `GenerateEvent` and `logGenerate()`
2. Wrap engine's `produce()` call
3. Run a simple plan, check the trace
4. Verify: can we see every generate call?
