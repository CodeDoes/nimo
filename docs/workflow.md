# Nimo Workflow — The User Journey

## What is nimo?

Nimo is a **deterministic harness** for a non-deterministic model. The coherence lives in the program, not the model.

## Core Workflows

### 1. Chat (Conversational)
```
User → "Tell me about AI" → Model responds → User follows up
```
- Bare conversational loop
- No plans, no tools, just generate
- Good for: quick questions, brainstorming, exploration

### 2. Plan & Execute (Goal-Directed)
```
User → "Write a story about X" → Plan produced → User reviews → User runs → Artifacts created
```
- Describe a goal
- See the plan (Nim script)
- Edit if needed
- Execute
- Get structured output

### 3. Story Pipeline (Creative)
```
User → "Write a 3-chapter story" → Outline → Characters → Wikis → Chapters → Validation
```
- Multi-phase generation
- Each phase produces artifacts
- Validation at each step
- Self-correcting

### 4. Memory & Recall (Contextual)
```
User → "Remember that I like X" → Stored → Later → "Based on what I told you..."
```
- Cross-turn context
- User preferences
- Workspace state

### 5. One-shot Generation (Batch)
```
User → "Generate Y from X" → Output → Done
```
- No conversation, just transform
- Good for: data processing, formatting, conversion

## The Unifying Thread

All workflows share:
- **One model backend** (CUDA/Vulkan)
- **One session** (message tree)
- **One state cache** (baked context)
- **One plan executor** (engine.run)

## The Question

What's the **primary** workflow? What do 80% of users do?

My guess: **Chat + Plan & Execute**. The rest are specialized cases.

What do you think?
