# 9200 — Trace

What the user sees in the CLI during execution. **Status: partial** —
`generate.nim` already streams tokens; the `▶/✔` step rendering below is the
target style for the engine (RFC 3600).

## Two observable layers

### Token-level (streaming, always)

Every sampled token appears the instant it is produced — `stdout.write` +
`flushFile` per token (as `src/generate.nim` does today). The user never waits
while the model generates.

```
The old man→ walked→ slowly→ down→ the...
```

### Step-level (engine checkpoints)

```
[nimo] ▶ 1/10 Generating wiki: Max...      ← ▶ active step
→ wiki/max.md

## Max
Robot ninja...                              ← content appears inline, streaming

[nimo] ✔ 1/10 (0.8s)                       ← ✔ done with time
[nimo] ▶ 2/10 ...
```

- `▶` = active step
- `✔` = done with time
- Content appears inline, token by token

## See Also

- [3600-engine.md](3600-engine.md) — the streaming executor contract
- [3500-plan-format.md](3500-plan-format.md) — the steps being traced