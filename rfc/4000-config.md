# Config

## What to include

- default workspace path (defaults to `.` but can be overwritten)
- model path
- model inference engine
- vocab path
- state baking paths
- personas
  - user intent
  - writer
  - manager
  - reader
  - critique
  - editor
  - planner
  - coder
- default model parameters
  - temperature
  - max tokens
  - top p
  - frequency penalty
  - presence penalty
  - stop sequences
- BNF settings
- logging settings
- eval settings
- test settings
- web app settings

## See Also

- [3000-pipeline.md](3000-pipeline.md) — pipeline uses config for model params
- [7000-env.md](7000-env.md) — engine selection maps to env config
