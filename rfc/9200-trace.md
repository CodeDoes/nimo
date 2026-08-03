# Trace

What the user sees in the CLI during execution.

## Examples

```
[nimo] ▶ 1/10 Generating wiki: Max...
→ wiki/max.md

## Max
Robot ninja. Stealth specialist...

[nimo] ✔ 1/10 Generating wiki: Max... (0.8s)
[nimo] ▶ 2/10 Generating wiki: Rob...
```

Active step shows `▶`, completed shows `✔` with elapsed time.
Generated content appears inline beneath each step.

## Trace Points

- Pipeline progress (step N/M)
- Tool call dispatch (which tool, args)
- Think block detection (`...`)
- Workspace operations
- Model timing (tokens/sec)

## Current Implementation

`src/cli.nim` — banner, colored output.
`src/macros.nim` — `benchmarkStep` logs timing.
