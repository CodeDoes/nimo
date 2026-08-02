`nimo chat`
`nimo session list`
`mkdir -r ~/.ws/temp5 && nimo chat -w ~/.ws/temp5`
`nimo chat -w .` // Default

### intent

#### user message examples

- Write a story
- Examine this workspace
- What do you think about X
- Tell me about
- Make it darker
- Continue with the next chapter
- Create a plan
- Write down everything you noticed about X

#### what i want

basically converting the user's message into a sequence of actions that can be executed by the system in a controlled manner with targeted prompts for each action. So in some way it needs to codify the vague intent. It might even be better to ask it to make code that can be executed.

### Super specific requirements
```txt
User: Create a story about a robot ninja named Max. 
He has a partner called Rob that is introduced in the second chapter. 
Create a wiki for 3 characters and the world they are in. 
Write the first 3 chapters and make an outline until chapter 10. (by chapter 10 I want Max to have fought and defeated the minor villian Ghastone)

Assitant: <think>
# Direct Considerations
The user wants to create a story. 
The specifics are:
- A robot ninja named Max
- A partner called Rob introduced in chapter 2
- A wiki for 3 characters and the world they are in
- First 3 chapters written
- Outline until chapter 10
- Max defeats the minor villian Ghastone by chapter 10
# Indirect Considerations
Is there anything else I need to consider that was not directly stated? 
- What is the world like?
- What is the tone of the story?
- What is the genre?
- What is the setting?
- What is the conflict?
- What is the theme?
- What is the style of writing?
I need to decide on these things before I can proceed.
# Decisions
- The world is a futuristic cyberpunk city.
- The tone is dark and gritty.
- The genre is action and adventure.
- The setting is a neon-lit city at night.
- The conflict is Max and Rob trying to stop Ghastone from taking over the city.
- The theme is the power of friendship and the struggle to be human.
- The style of writing is descriptive and immersive.
# Actions
- Create a wiki for the characters and the world.
- Write the first 3 chapters.
- Create an outline until chapter 10.
# Validations
- For each chapter, I need to ensure that the story is engaging and the characters are well-developed.
- For the outline, I need to ensure that the plot is coherent and the conflict is escalating.
- For the wiki, I need to ensure that the information is accurate and well-organized.
- I need to ensure that the story is consistent with the decisions made.
Okay I have all the information I need to proceed.</think>
I will now create a plan using the following provided procedures:
<code lang="nim">
import std/[os, strformat, tables]

type
  ModelConfig = object
    name: string
    temperature: float
    topP: float
    seed: int

  ContextState = ref object
    decisions: Table[string, string]
    artefacts: Table[string, string]

  Action = ref object
    id: string
    targetPath: string
    config: ModelConfig
    buildPrompt: proc(ctx: ContextState): string

  Pipeline = object
    actions: seq[Action]

proc runModel(cfg: ModelConfig, prompt: string): string =
  result = fmt"[Model: {cfg.name} | Seed: {cfg.seed}]\n{prompt}\n---> Output"

proc execute(pipe: Pipeline) =
  let ctx = ContextState(
    decisions: {
      "World": "Futuristic cyberpunk city",
      "Tone": "Dark, gritty",
      "Setting": "Neon-lit city at night",
      "Conflict": "Max and Rob vs Ghastone",
      "Style": "Descriptive, immersive"
    }.toTable,
    artefacts: initTable[string, string]()
  )

  for idx, action in pipe.actions:
    echo fmt"=== Step {idx + 1}/{pipe.actions.len}: {action.id} ==="
    let actionPrompt = action.buildPrompt(ctx)
    let output = runModel(action.config, actionPrompt)
    
    ctx.artefacts[action.id] = output
    
    if action.targetPath.len > 0:
      createDir(action.targetPath.splitFile().dir)
      writeFile(action.targetPath, output)
      echo fmt"Saved: {action.targetPath}\n"

proc buildStoryPipeline(): Pipeline =
  let defaultConfig = ModelConfig(
    name: "rwkv-7-world",
    temperature: 0.1,
    topP: 0.2,
    seed: 42
  )

  # Action 1: Wiki (Targeted inclusion: core entities and setting only)
  let actWiki = Action(
    id: "wiki",
    targetPath: "wiki/world_and_characters.md",
    config: defaultConfig,
    buildPrompt: proc(ctx: ContextState): string =
      fmt"""
Setting: {ctx.decisions["Setting"]}
Tone: {ctx.decisions["Tone"]}

Target Entities:
- Max (Robot Ninja)
- Rob (Partner)
- Ghastone (Minor Villain)
- World ({ctx.decisions["World"]})

Task: Generate reference entries for the specified target entities.
"""
  )

  # Action 2: Chapter 1 (Targeted inclusion: Max and World setting only)
  let actCh1 = Action(
    id: "ch1",
    targetPath: "chapters/01.md",
    config: defaultConfig,
    buildPrompt: proc(ctx: ContextState): string =
      fmt"""
Tone: {ctx.decisions["Tone"]}
Style: {ctx.decisions["Style"]}

Focus Entity: Max
Setting: {ctx.decisions["Setting"]}

Task: Write Chapter 1 detailing Max's initial operations within the city.
"""
  )

  # Action 3: Chapter 2 (Targeted inclusion: Ch1 outcome + Rob introduction)
  let actCh2 = Action(
    id: "ch2",
    targetPath: "chapters/02.md",
    config: defaultConfig,
    buildPrompt: proc(ctx: ContextState): string =
      fmt"""
Previous Chapter Summary:
{ctx.artefacts.getOrDefault("ch1", "N/A")}

Active Characters: Max, Rob

Task: Write Chapter 2. Introduce Rob into the narrative as Max's new partner.
"""
  )

  # Action 4: Chapter 3 (Targeted inclusion: Ch2 outcome + Ghastone threat hooks)
  let actCh3 = Action(
    id: "ch3",
    targetPath: "chapters/03.md",
    config: defaultConfig,
    buildPrompt: proc(ctx: ContextState): string =
      fmt"""
Previous Chapter Summary:
{ctx.artefacts.getOrDefault("ch2", "N/A")}

Active Conflict: {ctx.decisions["Conflict"]}

Task: Write Chapter 3 detailing Max and Rob discovering traces of Ghastone's operations.
"""
  )

  # Action 5: Outline (Targeted inclusion: Ch3 endpoint + Ch10 conclusion target)
  let actOutline = Action(
    id: "outline",
    targetPath: "outline.md",
    config: defaultConfig,
    buildPrompt: proc(ctx: ContextState): string =
      fmt"""
Narrative State at Ch3 End:
{ctx.artefacts.getOrDefault("ch3", "N/A")}

Milestone (Chapter 10): Max fights and defeats Ghastone.

Task: Generate a chapter-by-chapter outline for Chapters 4 through 10 leading to the specified milestone.
"""
  )

  result.actions = @[actWiki, actCh1, actCh2, actCh3, actOutline]

when isMainModule:
  let pipe = buildStoryPipeline()
  execute(pipe)
</code>
```
