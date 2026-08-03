# 1100 — Message Format

Raw text format for each part type in a session.

## System Part

```
System: You are a helpful assistant
```

## User Part

```
User: Hello there!
```

## Think Part

Model thinks before responding. Hidden from user by default.

```
Assistant: 
<model is thinking...>
Hi there! How can I help?
```

## Text Part

Normal assistant response.

```
Assistant: Hi! How can I assist you today?
```

## Tool Call Part

Model requests to use a tool.

```
Assistant: 
<tool_call>{"get_weather": {"location": "Boston, MA"}}</tool_call>
```

## Tool Result Part

Result injected by NIMO after tool execution.

```
User: <tool_result>72°F, sunny</tool_result>

Assistant: 
```

## Multi-Tool Call

```
Assistant: 
<tool_call>[{"get_weather": {"location": "Boston"}}, {"get_weather": {"location": "NYC"}}]</tool_call>
```
