# 1000 — Session

Session format emulating pi agent sessions.

## Session Header

```jsonl
{"type":"session","version":3,"id":"uuid","timestamp":"2026-08-03T14:47:08.723Z","cwd":"/home/kit/dev/nimo","parentSession":"..."}
```

## Message Structure

```jsonl
{"type":"message","id":"uuid","parentId":"uuid","timestamp":"...","message":{"role":"...","content":[...]}}
```

## Content Types

### Text

```json
{"type":"text","text":"Hello!"}
```

### Thinking

```json
{"type":"thinking","thinking":"I should respond...","thinkingSignature":"..."}
```

### Tool Call

```json
{"type":"toolCall","id":"call_xxx","name":"bash","arguments":{"command":"ls"}}
```

### Tool Result

```json
{"type":"toolResult","toolCallId":"call_xxx","toolName":"bash","content":[{"type":"text","text":"output"}],"isError":false}
```

## Example Session

```jsonl
{"type":"session","version":3,"id":"019fc817","timestamp":"2026-08-03T14:47:08Z","cwd":"/home/kit/dev/nimo"}
{"type":"message","id":"msg1","parentId":null,"timestamp":"...","message":{"role":"user","content":[{"type":"text","text":"Write a story"}]}}
{"type":"message","id":"msg2","parentId":"msg1","timestamp":"...","message":{"role":"assistant","content":[{"type":"thinking","thinking":"I should create a pipeline...","thinkingSignature":"..."},{"type":"toolCall","id":"call1","name":"run_pipeline","arguments":{"intent":"Write a cyberpunk story"}}],"stopReason":"toolUse"}}
{"type":"message","id":"msg3","parentId":"msg2","timestamp":"...","message":{"role":"toolResult","toolCallId":"call1","toolName":"run_pipeline","content":[{"type":"text","text":"[nimo] ▶ 1/10... ✔ 1/10..."}],"isError":false}}
{"type":"message","id":"msg4","parentId":"msg3","timestamp":"...","message":{"role":"assistant","content":[{"type":"text","text":"Here's your story!"}}]}}
```

## Usage Tracking

```json
{"input":2081,"output":130,"cacheRead":0,"cacheWrite":0,"reasoning":26,"totalTokens":2211,"cost":{"input":0,"output":0,"total":0}}
```

## See Also

- [1100-message-format.md](1100-message-format.md) — raw text format
- [9100-logging.md](9100-logging.md) — JSONL logging
