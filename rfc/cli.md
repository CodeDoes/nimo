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
  7. Write Chapter 2
  8. Draft outline
  9. Write Chapter 3
  10. Finalize outline

[nimo] ▶ 1/10 Generating wiki: Max...
→ wiki/max.md

## Max
Robot ninja. Stealth specialist. Built for covert ops in dense urban environments. Wears adaptive camouflage plating that bends light around his frame. Primary weapons: mono-filament wire whips and subdermal blade arrays. Personality: stoic, observant, dry wit surfaces only with trusted allies.

[nimo] ✔ 1/10 Generating wiki: Max... (0.8s)
[nimo] ▶ 2/10 Generating wiki: Rob...

## Rob
Heavy ordnance specialist. Tactical partner assigned after Max's solo incidents escalated. Carries a rotary cannon mounted to his left shoulder. Personality: boisterous, loyal, treats combat like a contact sport. Frequently cracks jokes while laying down suppressive fire.

[nimo] ✔ 2/10 Generating wiki: Rob... (0.7s)
[nimo] ▶ 3/10 Generating wiki: Ghastone...

## Ghastone
Cybernetic syndicate crime boss. Controls the Neon District through a network of augmented enforcers. Known for his signature — a silver gasmask shaped like a weeping face. Motive: wants to monopolize synthetic memory trading, which requires eliminating independent operators like Max.

[nimo] ✔ 3/10 Generating wiki: Ghastone... (0.9s)
[nimo] ▶ 4/10 Generating wiki: Neo-Kuroba...

## Neo-Kuroba
High-tech neon cyberpunk city. 200+ stories of vertical sprawl. The rich live in the spires above the cloud layer. The poor navigate the Undercity — a labyrinth of repurposed infrastructure lit by holographic advertising. Rain is constant; the atmosphere processors leak acidic mist. Corporate banners replace flags.

[nimo] ✔ 4/10 Generating wiki: Neo-Kuroba... (0.8s)
[nimo] ▶ 5/10 Extracting context buffers...

=== Max ===
Combat: precision strikes, mono-filament wire whips, subdermal blade arrays
Defense: adaptive camouflage plating, light-bending stealth
Personality: stoic, observant, dry wit with trusted allies

=== Rob ===
Combat: rotary cannon, suppressive fire tactics
Personality: boisterous, loyal, treats combat like contact sport
Role: tactical partner, backup cover

=== Ghastone ===
Identity: cybernetic syndicate crime boss
Control: Neon District via augmented enforcers
Signature: silver gasmask shaped like weeping face
Motive: monopolize synthetic memory trading

=== Neo-Kuroba ===
Setting: 200+ story vertical sprawl, neon-lit cyberpunk city
Classes: rich in spires above clouds, poor in Undercity below
Atmosphere: constant acidic rain, holographic advertising
Power: corporate banners replace national flags

[nimo] ✔ 5/10 Extracting context buffers... (0.5s)
[nimo] ▶ 6/10 Writing Chapter 1...

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

[nimo] ✔ 6/10 Writing Chapter 1... (12.4s)
[nimo] ▶ 7/10 Writing Chapter 2...

Chapter 2: Rob found Max in the same spot three nights later — same rusted bulkhead, same posture, same silence. "You know," he announced, rotating his rotary cannon to a comfortable resting position, "most people make friends. You make dead bodies. It's a whole thing."

Max didn't turn. He was listening to the city breathe — the hum of atmospheric processors, the distant wail of corporate enforcement drones, the whispered conversations of the Undercity's denizens. "They're moving synthetic memory through the old filtration plant. Sub-level three. Eight canisters per run."

"Then let's go take them," Rob said, already moving. "Or, you know, let me go take them while you stand there looking broody. Your choice."

Max almost smiled. Almost. "They'll have enforcers. You need cover."

"I'm the cover," Rob said, patting his shoulder-mounted cannon. "You're the knife. We're a team."

[nimo] ✔ 7/10 Writing Chapter 2... (9.2s)
[nimo] ▶ 8/10 Drafting outline...

Chapter 4: First contact with Ghastone's inner circle. Max and Rob infiltrate a synthetic memory auction.
Chapter 5: Discovery — Ghastone's monopoly requires eliminating all independent memory traders.
Chapter 6: Rob captured. Max must choose between rescue and the mission.
Chapter 7: Max goes underground, uses his stealth to sabotage Ghastone's distribution network.
Chapter 8: Rob escapes, reunites with Max. They devise a plan to strike at the source.
Chapter 9: Assault on Ghastone's spire. Final confrontation.
Chapter 10: Ghastone defeated. Max and Rob stand atop the Neon District, looking toward a freer city.

[nimo] ✔ 8/10 Drafting outline... (4.1s)
[nimo] ▶ 9/10 Writing Chapter 3...

Chapter 3: The filtration plant was a tomb of corroded pipes and stagnant water. Max moved through it like a shadow, his adaptive plating rendering him invisible to thermal and visual sensors. Rob hung back on the upper levels, his rotary cannon a low rumble of suppressive fire whenever enforcers surged forward.

Eight canisters. Eight lives worth of stolen memories — people's experiences, their loves, their losses, all bottled and sold to the highest bidder in the spires above.

Max tagged the last canister and triggered the beacon. Then he heard it — a voice, distorted by a cybernetic vocoder, echoing through the plant's central chamber.

"I know you're here, little ninja. I've been expecting you."

Ghastone.

[nimo] ✔ 9/10 Writing Chapter 3... (11.8s)
[nimo] ▶ 10/10 Finalizing outline...

Final Outline (Chapters 4–10):
- Ch4: Infiltrate synthetic memory auction
- Ch5: Discover Ghastone's elimination mandate
- Ch6: Rob captured, Max's choice
- Ch7: Max sabotages distribution network
- Ch8: Rob escapes, plan devised
- Ch9: Assault on Ghastone's spire
- Ch10: Ghastone defeated, city freed

[nimo] ✔ 10/10 Finalizing outline... (2.3s)
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
