## Common
```txt
System: You are a helpful assistant

User: Hello there!

Assistant: <think>Okay, the user has greeted me. I should respond in a friendly manner.</think>Hi there! How can I assist you today?
```

## Tool Calling
```txt
System: You are a helpful assistant
<tools>{"get_weather": {"description": "Get the current weather in a given location", "parameters": {"type": "object", "properties": {"location": {"type": "string", "description": "The city and state, e.g. San Francisco, CA"}}, "required": ["location"]}}}</tools>

User: What's the weather like in Boston today?

Assistant: <think>I need to get the current weather in Boston. I have a tool called get_weather that can help with this.</think><tool_call>{"get_weather": {"location": "Boston, MA"}}</tool_call>

User: <tool_result>{"get_weather":{"location":"Boston, MA","temperature":"72","unit":"fahrenheit","forecast":"Sunny"}}</tool_result>

Assistant: <think>The weather in Boston is 72 degrees Fahrenheit and sunny.</think>The current weather in Boston is 72°F and sunny.

User: That's hot... I guess I'm used to it.

Assistant: <think>The user is used to the weather in Boston.</think>I'm glad you're used to it! Boston can be quite warm in the summer.

User:
```

## Multi tool call

When calling multiple tools, the assistant should use an array.

```txt
System: You are a helpful assistant
<tools>{"get_weather": {"description": "Get the current weather in a given location", "parameters": {"type": "object", "properties": {"location": {"type": "string", "description": "The city and state, e.g. San Francisco, CA"}}, "required": ["location"]}}}</tools>

User: What's the weather like in Boston and New York today?

Assistant: <think>I need to get the current weather in Boston and New York. I have a tool called get_weather that can help with this.</think><tool_call>[{"get_weather": {"location": "Boston, MA"}}, {"get_weather": {"location": "New York, NY"}}]</tool_call>

User: <tool_result>[{"get_weather":{"location":"Boston, MA","temperature":"72","unit":"fahrenheit","forecast":"Sunny"}}, {"get_weather":{"location":"New York, NY","temperature":"75","unit":"fahrenheit","forecast":"Cloudy"}}]</tool_result>

Assistant: <think>The weather in Boston is 72 degrees Fahrenheit and sunny. The weather in New York is 75 degrees Fahrenheit and cloudy.</think>The current weather in Boston is 72°F and sunny. The current weather in New York is 75°F and cloudy.

User: Hmm. Do you think I should wear a jacket?

Assistant: <think>It's sunny in Boston, but cloudy in New York. I should probably recommend a jacket for New York.</think>I would recommend wearing a jacket in New York, but you might not need one in Boston.
```
