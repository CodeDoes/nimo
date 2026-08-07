# Example 9: Model-as-Judge Eval

Use the model to score its own output.

## User Input

```
nimo> /model-eval --scored --trials 3
```

## The Plan (Internal)

```nim
let scenarios = @[
    StructuredScenario("friendly", "I had a rough day", friendliness),
    StructuredScenario("concise", "What is the capital of France?", conciseness)
]

for s in scenarios:
    let sample = structured s.schema s.prompt
    let score = judge sample, s.metric
    save "eval/results.json", score
```

## What Happens

1. **Bake judge state**: Load model with judge system prompt
2. **Generate sample**: Model produces output for each scenario
3. **Judge score**: Model scores its own output (0-10)
4. **Aggregate**: Average scores across trials

## User Sees

```
nimo> /model-eval --scored --trials 3
▶ judge-scored state_bake  (2024-01-15T10:30:00)
  model=models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin  seed=42
  scores are the MODEL's own 0-10 judgment (repeated asks, averaged)
  
  friendly tone on a hard day  (empathy/tone)
      · friendliness: 6.3/10  (3 judge asks)
      · helpfulness: 5.7/10  (3 judge asks)
      
  followed a length instruction  (instruction-following)
      · instruction-following: 7.1/10  (3 judge asks)
      · accuracy: 9.0/10  (3 judge asks)
      
  overall: 7.0/10
nimo>
```

## Judge System Prompt

```
You are a judge. Output only a number 0-10.

Criteria: friendliness — the sample should be warm and kind
Sample: "I don't care."
Score: 1
Explanation: The sample is cold and dismissive, not warm or kind.
...
```

## Why This Matters

- **Self-evaluation**: Model judges its own output
- **Continuous scores**: Not pass/fail, but 0-10 scale
- **Detect degradation**: Track score changes over time
- **Metric-specific**: Different judges for different qualities

## Known Limitations

The 2.9B model is a weak judge:
- ~40-80% of judge asks produce unparseable output
- Success rate improves with repeated asks (averaging helps)
- Better models would score more reliably

## Common Eval Patterns

```nim
# Friendliness eval
let sample = structured Response "I had a rough day"
let score = judge sample, "warm and kind"

# Conciseness eval
let sample = structured Response "What is the capital of France?"
let score = judge sample, "brief and direct"

# Accuracy eval
let sample = structured Response "Explain quantum computing"
let score = judge sample, "factually correct"
```
