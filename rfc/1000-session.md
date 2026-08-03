# Session Model

A session is an array of messages and an array of branches.
A branch is an array of message indexes.
A message is a part type and part content.

## Part Types

- `system` — priming the model to respond in a certain way
- `user` — the actual user input
- `think` — from ``
- `tool_call` — from `<tool_call>` to `</tool_call>`. Model emits token-id 0 after this.
- `tool_result` — from `\n\nUser: <tool_result>` to `</tool_result>\n\nAssistant:`
- `text` — normal text after `Assistant:`

## See Also

- [1100-chat.md](1100-chat.md) — message format examples
- [6000-src.md](6000-src.md) — where this lives in `app/session.nim`
