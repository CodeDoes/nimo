# State Bake

Unique hash to determine if state bake cache is valid.
Hash based on:
- bake examples
- rwkv model hash
- rwkv vocab hash

Use token id 0 between examples. Basically anywhere you would want the assistant to naturally stop so the system can add its own parts or when it wants to hand over to the user. (tool_call, think end maybe? text end, response finished)

## See Also

- [config.md](05-config.md) — state baking paths in config
- [pipeline.md](03-pipeline.md) — pipeline may use baked state for caching
