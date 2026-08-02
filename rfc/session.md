a session is a array of message
and an array of branches
a branch is an array of message indexes
a message is a part type and a part content

## part types
- system
- user
- think
- tool_call
- tool_result
- text

### Think 
from `<think>` to `</think>` is a think part.
### Tool Call
from `<tool_call>` to `</tool_call>` is a tool call part. It is trained to emit a token-id 0 after this.
### Tool Result
from `\n\nUser: <tool_result>` to `</tool_result>\n\nAssistant:` is a tool result part
### Text
Is just the normal text part after turn `Assistant:`.
### User
Is the ACTUAL user input part. The reason `User:` is used for tool_result is because assistants used to be used like that.
### System
Is priming the model to respond in a certain way.
