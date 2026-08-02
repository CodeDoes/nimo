## What is this file for?

CLI interface, user workflow, and intent-to-DSL extraction.

## Commands

```
nimo chat               # Interactive TUI chat
nimo chat -w ~/.ws/myproject
nimo generate <prompt>  # One-shot
nimo bake <prompt>      # Pre-bake state
nimo dashboard          # Full-screen TUI
nimo run pipeline.nim   # Execute a pipeline script
nimo workspace create --set-default
```

## Workspace

```
nimo workspace create --set-default
# → creates ~/.ws/YYYYMMddHHmmss_<random_slug>/
# → sets it as default for current dir

nimo chat
# → uses default workspace
#   release: cwd (.)
#   dev:     last workspace from previous session

nimo chat -w ~/.ws/myproject
# → explicit workspace override
```

**Release:** `default_workspace = .` (cwd)
**Dev:** `default_workspace = <last_workspace>` (from previous session)

## Intent → DSL

User gives vague intent. System extracts it into a `pipeline.nim`, then runs it.

```
$ nimo chat
> Write a cyberpunk story. Robot ninja Max. Partner Rob in chapter 2.
> Wiki for 3 chars + world. First 3 chapters. Outline to chapter 10.
> Max defeats Ghastone by chapter 10.

[nimo] Creating plan...
[nimo] Plan:
  1. Generate wiki: Max
  2. Generate wiki: Rob
  3. Generate wiki: Ghastone
  4. Generate wiki: Neo-Kuroba
  5. Extract context buffers
  6. Write Chapter 1
  7. Write Chapter 2 + draft outline
  8. Write Chapter 3
  9. Finalize outline

[nimo] ▶ 1/9 Generating wiki: Max...

## Max
Robot ninja. Stealth specialist. Built for covert ops in dense urban environments. Wears adaptive camouflage plating that bends light around his frame. Primary weapons: mono-filament wire whips and subdermal blade arrays. Personality: stoic, observant, dry wit surfaces only with trusted allies.

[nimo] ✔ 1/9 Generating wiki: Max... (0.8s)
[nimo] ▶ 2/9 Generating wiki: Rob...

## Rob
Heavy ordnance specialist. Tactical partner assigned after Max's solo incidents escalated. Carries a rotary cannon mounted to his left shoulder. Personality: boisterous, loyal, treats combat like a contact sport. Frequently cracks jokes while laying down suppressive fire.

[nimo] ✔ 2/9 Generating wiki: Rob... (0.7s)
[nimo] ▶ 3/9 Generating wiki: Ghastone...

## Ghastone
Cybernetic syndicate crime boss. Controls the Neon District through a network of augmented enforcers. Known for his signature — a silver gasmask shaped like a weeping face. Motive: wants to monopolize synthetic memory trading, which requires eliminating independent operators like Max.

[nimo] ✔ 3/9 Generating wiki: Ghastone... (0.9s)
[nimo] ▶ 4/9 Generating wiki: Neo-Kuroba...

## Neo-Kuroba
High-tech neon cyberpunk city. 200+ stories of vertical sprawl. The rich live in the spires above the cloud layer. The poor navigate the Undercity — a labyrinth of repurposed infrastructure lit by holographic advertising. Rain is constant; the atmosphere processors leak acidic mist. Corporate banners replace flags.

[nimo] ✔ 4/9 Generating wiki: Neo-Kuroba... (0.8s)
[nimo] ▶ 5/9 Extracting context buffers...

Max context: [precision strikes, mono-filament wire, adaptive camo, stoic, dry wit]
Rob context: [rotary cannon, suppressive fire, boisterous, loyal]
Ghastone context: [silver gasmask, Neon District, synthetic memory monopoly]
Neo-Kuroba context: [vertical sprawl, Undercity, acidic rain, corporate banners]

[nimo] ✔ 5/9 Extracting context buffers... (0.5s)
[nimo] ▶ 6/9 Writing Chapter 1...

Chapter 1: The neon rain fell like static across Max's visor as he moved through the Undercity's lower levels. His adaptive plating shifted from black to the exact shade of the rusted bulkhead he pressed against — near perfect. Below him, three Ghastone enforcers patrolled the corridor, their cybernetic optics scanning for anything that didn't belong.

Max didn't belong anywhere. That was the point.

The target was a synthetic memory cache hidden in what used to be a water filtration plant. Ghastone's people had been moving product through here for months. Max's employer — an anonymous contact who communicated only through encrypted dead drops — wanted the route exposed.

He counted breaths. One. Two. Three.

The wire whips unspooled from his forearms, silent as falling dust. Two enforcers dropped before they registered the sound — or the lack thereof. The third turned, mouth opening to shout, and Max was already on him, mono-filament blade extended from his index finger, pressing against the gap between helmet and neck armor.

"Where's the cache?" he whispered.

The enforcer's optics flickered — he was sending a distress ping. Max applied pressure. The ping stopped.

He found the route three levels down, behind a false wall of corroded piping. Eight canisters of synthetic memory, enough to buy a spire apartment for a year. He tagged them with a tracking beacon and uploaded the coordinates to his dead drop.

As he moved back toward the surface, his comms crackled. Rob's voice, loud and obnoxious even through the static: "Hey shiny, you alive down there? I was starting to think you got eaten by rats again."

Max didn't answer. He never did over open channels. But something almost like amusement touched the corner of his mouth as he melted into the neon-lit darkness above.

[nimo] ✔ 6/9 Writing Chapter 1... (12.4s)
[nimo] Done. Artifacts in ~/.ws/myproject/
```

Active step shows `▶`, completed show `✔` with elapsed time.
Generated content appears inline beneath each step — full output, not truncated.
`Ctrl+O` folds large content blocks (optional).

The generated `pipeline.nim` is saved to the workspace so the user can inspect/edit it.

## Flow

1. **Capture** — user types intent in chat
2. **Extract** — LLM analyzes intent, produces a `pipeline.nim` script
3. **Plan** — topological sort produces ordered steps with parallel groups
4. **Execute** — `nim script` runs the pipeline, shows progress per step
5. **Return** — artifacts served back to user

See `rfc/pipeline.md` for the DSL spec.
