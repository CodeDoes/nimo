# Example 10: Key Patterns

Reusable templates for common planning patterns.

## Pattern 1: Generate → Validate → Save

```nim
let x = structured Schema "prompt"
if check(x):
    save "path", x
else:
    let y = structured Schema "revise: " & x
    save "path", y
```

**Use when:** You need quality gates on generated output.

**Variants:**
```nim
# Single revision
if not validate(x):
    x = structured Schema "fix: " & x

# Multiple revisions (loop)
for i in 1..3:
    if validate(x): break
    x = structured Schema "revise (" & $i & "): " & x

# Different schema for revision
if not check(x, SchemaV1):
    x = structured SchemaV2 "fix schema: " & x
```

---

## Pattern 2: Loop over List

```nim
for item in list:
    let child = structured ChildSchema "process: " & item
    save "output/" & item.id & ".json", child
```

**Use when:** You need to generate one output per input item.

**Variants:**
```nim
# With index
for i, item in enumerate(list):
    let child = structured ChildSchema "item " & $i & ": " & item
    save "output/" & $i & ".json", child

# Filtered loop
for item in list:
    if item.active:
        let child = structured ChildSchema "active: " & item
        save "output/" & item.id & ".json", child

# Accumulate results
var results: seq[string]
for item in list:
    let child = structured ChildSchema "process: " & item
    results.add(child.result)
save "all.json", results
```

---

## Pattern 3: Chain Variables

```nim
let a = structured A "..."
let b = structured B "from: " & a
let c = structured C "from: " & b
save "final.json", c
```

**Use when:** Each step depends on the previous output.

**Variants:**
```nim
# With intermediate inspection
let a = structured A "..."
say "a = " & a.someField
let b = structured B "from: " & a
save "b.json", b

# Parallel chains
let a = structured A "..."
let b = structured B "..."
let c = structured C "from: " & a & " and " & b
```

---

## Pattern 4: Memory Injection

```nim
memory "important context"
# ... later ...
let result = structured Result "consider: " & recall("important context")
```

**Use when:** You need cross-turn or cross-plan context.

**Variants:**
```nim
# Multiple memories
memory "User prefers concise answers"
memory "Current project: nimo"
memory "Deadline: next week"

# Recall all
let all = recall("all")
let result = structured Result "consider: " & all

# Recall specific
let pref = recall("preferences")
let result = structured Result pref
```

---

## Pattern 5: Conditional Execution

```nim
let x = structured Schema "..."
if x.someField.len > 0:
    let y = structured Schema2 "from: " & x
    save "y.json", y
else:
    say "x was empty"
```

**Use when:** Behavior depends on previous output.

**Variants:**
```nim
# Multiple conditions
if x.quality >= 0.8:
    save "good.json", x
elif x.quality >= 0.5:
    let y = structured Schema "revise: " & x
    save "ok.json", y
else:
    say "too low quality"

# Nested conditions
if x.hasField:
    if x.field.len > 100:
        save "long.json", x
    else:
        save "short.json", x
```

---

## Pattern 6: Pipeline with Checkpoints

```nim
say "starting"
let a = structured A "..."
save "a.json", a
say "step 1 done"

for item in a.items:
    let b = structured B "from: " & item
    save "b_" & item.id & ".json", b
say "step 2 done"

let c = structured C "from: " & a
save "c.json", c
say "complete"
```

**Use when:** Long-running plans need progress visibility.

**Variants:**
```nim
# With error handling
try:
    let a = structured A "..."
    save "a.json", a
except:
    say "failed at step 1"
    
# With resume
if fileExists("checkpoint.json"):
    let a = load "checkpoint.json"
else:
    let a = structured A "..."
    save "checkpoint.json", a
```

---

## Pattern 7: Transform Data

```nim
let raw = load "input.json"
let transformed = structured Transform "convert: " & raw
save "output.json", transformed
```

**Use when:** Converting between formats or schemas.

**Variants:**
```nim
# Multiple transforms
let step1 = structured Transform1 "..."
let step2 = structured Transform2 "from: " & step1
let step3 = structured Transform3 "from: " & step2
save "final.json", step3

# Round-trip
let original = load "input.json"
let exported = structured Export "..." & original
let imported = structured Import "..." & exported
save "roundtrip.json", imported
```

---

## Pattern 8: Aggregate Results

```nim
var results: seq[string]
for item in items:
    let r = structured Result "process: " & item
    results.add(r.output)
save "aggregated.json", results
```

**Use when:** Collecting multiple outputs into one.

**Variants:**
```nim
# With metadata
var results: seq[Result]
for item in items:
    let r = structured Result "process: " & item
    r.metadata = "processed at " & now()
    results.add(r)
save "results.json", results

# Filtered aggregation
var goodResults: seq[string]
for item in items:
    let r = structured Result "process: " & item
    if r.quality >= 0.7:
        goodResults.add(r.output)
save "good.json", goodResults
```
