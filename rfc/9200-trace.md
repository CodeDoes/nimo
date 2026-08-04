# 9200 — Trace

What user sees in CLI during execution. **Status: partial** — the harness and tools print `[nimo]` progress lines and per-turn stats; the `▶/✔` step rendering below is the target style.

## Example output

```
[nimo] ▶ 1/10 Generating wiki: Max...
→ wiki/max.md

## Max
Robot ninja...

[nimo] ✔ 1/10 (0.8s)
[nimo] ▶ 2/10 Generating wiki: Rob...
```

- `▶` = active step
- `✔` = done with time
- Content appears inline
