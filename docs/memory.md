# Memory & Notes — How It Works

NIMO has a small memory system so the model can "remember" characters, facts,
and notes between turns — without re-reading everything every time.

## The pieces

| Piece | What it does |
|-------|--------------|
| FIAAS | The storage + search engine. Stands for "Fictional AI Associative Storage". |
| MemoryStore | The friendly wrapper you actually use. |
| Workspace `wiki/` | The human-readable, on-disk notes (markdown files). |

## FIAAS: storing a memory

When you store a piece of text ("Kael is a retired pilot who hates the rain"):

1. FIAAS gives it an id (`mem_0`, `mem_1`, ...).
2. It turns the text into a **fixed-size vector** — a list of 64 numbers.
   This is done with a hash trick: the same text always produces the same
   vector (deterministic), and different texts produce different vectors.
3. The entry (text + vector + category + metadata) is added to the store.
4. Optionally saved to a JSON file so it survives restarts.

> Note: this is a *simulated* embedding — it's not a real neural embedding
> model, but the hash vectors are good enough for the MVP to rank related
> memories.

## FIAAS: searching

When you search for "who is the pilot who hates rain":

1. The query is turned into the same kind of vector.
2. Every stored entry's vector is compared to the query with **cosine
   similarity** (a standard "how close are these two directions" measure).
3. Entries are sorted best-first and the top K (default 5) are returned.
4. `searchByCategory` does a simpler thing: just filters by category
   (character / scene / plot / theme).

## MemoryStore: the friendly layer

`MemoryStore` wraps FIAAS and adds convenience:

- `addMemory(text, category)` → store a memory, get its id.
- `searchMemory(query)` → get the top matching texts.
- `rememberCharacter(name, description)` → store a character fact *and* keep a
  name → memory-id map so you can fetch it back directly.
- `getCharacterMemory(name)` → fetch that character's stored description.
- `getRelevantContext(currentText)` → search for the 3 most relevant memories
  and return them as a short text block (bounded to ~500 characters) — this is
  what you'd inject into a prompt so the model "remembers".

## How it plugs into story writing

1. A character is introduced → `rememberCharacter("Kael", "retired pilot...")`.
2. A later chapter generation needs context → `getRelevantContext("Kael")`
   returns the stored facts.
3. Those facts are added to the prompt (wiki context) → the model writes
   consistently without reading the entire story.

## Take note / extract data

For longer pipelines there are two helpers that follow the same idea:

- **Extract** (`extractStep`): given input text and a filter ("names of all
  characters"), the model pulls out just the requested facts.
- **Summarize** (`summarizeStep`): condenses input into bullet points.

Both produce text that can be stored as a memory or written to a file.

## Where memory files live

- Memory JSON: wherever you choose (workspace `.nimo/` is the natural spot).
- Wiki notes: `~/.ws/<name>/wiki/<character_name>.md`.
- Pipeline artifacts: `./.nimo/pipelines/`.

## The whole flow at a glance

```
store:  text -> hash vector -> FIAAS entry -> (JSON file)
search: query -> hash vector -> cosine compare -> top K texts
chat:   getRelevantContext() -> inject into prompt -> model remembers
```
