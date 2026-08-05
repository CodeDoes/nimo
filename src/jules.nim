## jules — a small CLI for spawning and watching Jules coding agents.
##
## A friendlier, queue-oriented wrapper around the Jules API than the shell
## script. The API key is NEVER hardcoded: it is read from $JULES_API_KEY or
## from `.env` (`JULES_API_KEY=...`) at the repo root, and never printed.
##
## Commands:
##   jules check                     Validate the key (masked)
##   jules spawn <repo> <prompt>     Create a session and add it to the local
##                                   queue (the everyday action)
##   jules queue                     List spawned sessions with PR/status
##   jules status <id>               One session: state + head of activities
##   jules watch [id]                Poll a session until it completes, showing
##                                   new activity lines (default: progress on
##                                   the most recent queued session)
##   jules activities <id>           Readable activity stream
##   jules prs                       Pull requests across queued/completed jobs
##   jules sessions                  Recent sessions from the API
##   jules send <id> "<msg>"         Message the agent
##   jules approve <id>              Approve a pending plan
##   jules archive-all [--limit N]   Archive every non-archived session
##
## Design notes (see AGENTS.md):
##   * Generation is a pure, offline-testable seam (the network `request` fn is
##     injected) so parsing/queue logic can be unit-tested with no API key.
##   * State lives in `.jules.json` next to the binary's cwd — a plain list of
##     {id, repo, prompt, createdAt}.
##   * Output is plain text + emoji; no manual, natural-language first.

import std/[os, strutils, json, times, httpclient, uri, base64, tables]

const
  BaseUrl* = "https://jules.googleapis.com/v1alpha"
  QueueFile = ".jules.json"

# ---------------------------------------------------------------------------
# Config / key resolution
# ---------------------------------------------------------------------------
proc envFile*(): string =
  ## `.env` next to cwd (the jules.sh convention: repo-root .env).
  getCurrentDir() / ".env"

proc resolveKey*(inline: string = ""): string =
  ## Returns the API key or "" (never prints it). Priority:
  ##   inline > $JULES_API_KEY > .env JULES_API_KEY=...   (quotes stripped)
  var key = inline
  if key.len == 0:
    key = getEnv("JULES_API_KEY")
  if key.len == 0 and fileExists(envFile()):
    for line in envFile().readFile().splitLines():
      if line.startsWith("JULES_API_KEY="):
        key = line["JULES_API_KEY=".len .. ^1]
        break
  # strip surrounding quotes just like jules.sh does (dotenv keeps them)
  key = key.strip(chars = {' ', '\t', '\r', '\n'})
  if key.len >= 2 and key[0] in {'\'', '"'} and key[^1] == key[0]:
    key = key[1 .. ^2]
  key

# ---------------------------------------------------------------------------
# Pure helpers (offline-testable)
# ---------------------------------------------------------------------------
proc stateIcon*(state: string): string =
  ## A tiny visual for a session state.
  case state.toLowerAscii()
  of "scheduled", "queued": "🕐"
  of "running", "active":   "▶"
  of "completed", "done":   "✅"
  of "failed", "error":     "❌"
  of "archived":            "🗄️"
  else:                     "○"

proc shorten*(s: string, n: int = 52): string =
  ## One-line truncation with ellipsis; newlines collapsed to spaces.
  let one = s.replace('\n', ' ').strip()
  if one.len <= n: one else: one[0 ..< n] & "…"

proc extractPrs*(sess: JsonNode): seq[string] =
  ## Pull PR urls out of a session's outputs[].pullRequest.
  result = @[]
  if sess.kind != JObject: return
  let outputs = sess{"outputs"}
  if outputs.isNil or outputs.kind != JArray: return
  for o in outputs:
    if o.kind != JObject: continue
    let pr = o{"pullRequest"}
    if not pr.isNil and pr.kind == JObject:
      let url = pr{"url"}
      if not url.isNil and url.kind == JString and url.str.len > 0:
        result.add(url.str)

proc niceTime*(ts: string): string =
  ## "2026-08-05T06:23:53...Z" -> "Aug 5 06:23"
  try:
    let t = parse(ts, "yyyy-MM-dd'T'HH:mm:ss", utc())
    t.format("MMM d HH:mm")
  except:
    ts

# ---------------------------------------------------------------------------
# API layer (network injected so the rest is testable)
# ---------------------------------------------------------------------------
type
  RequestFn* = proc(verb, path: string, body: JsonNode): string

proc realRequest*(key: string): RequestFn =
  ## Default network implementation. Closes over the key only; never stored.
  proc req(verb, path: string, body: JsonNode): string =
    let client = newHttpClient(timeout = 60000)
    defer: client.close()
    var headers = newHttpHeaders({
      "X-Goog-Api-Key": key,
      "Content-Type": "application/json"
    })
    var resp: Response
    if body.isNil:
      resp = client.request(BaseUrl & path, httpMethod = verb, headers = headers)
    else:
      resp = client.request(BaseUrl & path, httpMethod = verb,
                            headers = headers, body = $body)
    resp.body
  req

proc parseOrErr*(body: string): JsonNode =
  ## Treat an API body as JSON; if it carries `.error`, raise it for the CLI.
  try:
    result = parseJson(body)
    if result.kind == JObject:
      let e = result{"error"}
      if not e.isNil:
        let msg = e{"message"}
        let m = if not msg.isNil and msg.kind == JString: msg.str else: body
        raise newException(IOError, "Jules API error: " & m)
  except JsonParsingError:
    raise newException(IOError, "API returned non-JSON:\n" & body)

# ---------------------------------------------------------------------------
# Queue (local registry of spawned jobs)
# ---------------------------------------------------------------------------
type
  QueuedJob* = object
    id*, repo*, prompt*, createdAt*: string

proc queuePath*(): string = getCurrentDir() / QueueFile

proc loadQueue*(): seq[QueuedJob] =
  if not fileExists(queuePath()): return @[]
  try:
    for n in queuePath().parseFile():
      if n.kind == JObject:
        result.add(QueuedJob(
          id: n{"id"}.getStr(""),
          repo: n{"repo"}.getStr(""),
          prompt: n{"prompt"}.getStr(""),
          createdAt: n{"createdAt"}.getStr("")))
  except:
    discard

proc saveQueue*(jobs: seq[QueuedJob]) =
  var arr = newJArray()
  for j in jobs:
    arr.add(%*{ "id": j.id, "repo": j.repo, "prompt": j.prompt,
                "createdAt": j.createdAt })
  queuePath().writeFile(arr.pretty)

proc addJob*(id, repo, prompt: string) =
  var jobs = loadQueue()
  jobs.add(QueuedJob(id: id, repo: repo, prompt: prompt,
                     createdAt: now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'")))
  saveQueue(jobs)

proc findJob*(id: string): QueuedJob =
  for j in loadQueue():
    if j.id == id: return j
  QueuedJob(id: id)

# ---------------------------------------------------------------------------
# Session listing / formatting
# ---------------------------------------------------------------------------
proc sessionTable*(sess: JsonNode): string =
  ## One line per session:  icon  id  title  PRs.
  var lines: seq[string]
  for s in sess:
    if s.kind != JObject: continue
    let id = s{"id"}.getStr("?")
    let title = s{"title"}.getStr("")
    let state = s{"state"}.getStr("")
    let created = niceTime(s{"createTime"}.getStr(""))
    var prs = extractPrs(s)
    if prs.len == 0:
      lines.add("  " & stateIcon(state) & " " & created & "  " & id &
                "  " & shorten(title))
    else:
      lines.add("  " & stateIcon(state) & " " & created & "  " & id &
                "  " & shorten(title) & "  → " & prs[0])
  if lines.len == 0: "  (none)"
  else: lines.join("\n")

# ---------------------------------------------------------------------------
# Activities formatting
# ---------------------------------------------------------------------------
proc activityLine*(a: JsonNode): string =
  ## One human-readable line per activity. Understands the real Jules shapes:
  ##   agentMessaged.agentMessage, userMessaged.message, planGenerated,
  ##   planApproved, sessionCompleted, sessionStateChanged.
  let t = niceTime(a{"createTime"}.getStr(""))
  let origin = a{"originator"}.getStr("?")

  proc bodyText(n: JsonNode): string =
    if n.isNil: return ""
    # plain string payload
    if n.kind == JString: return n.str
    # nested object with a *Message field
    if n.kind == JObject:
      for k, v in n:
        if k.endsWith("Message") and v.kind == JString and v.str.len > 0:
          return v.str
    ""

  var label = ""
  for kind in ["planGenerated", "planApproved", "sessionCompleted",
               "sessionStateChanged", "agentMessaged", "userMessaged",
               "agentUsedTool", "sessionCancelled"]:
    let payload = a{kind}
    if not payload.isNil:
      let txt = bodyText(payload)
      case kind
      of "planGenerated":
        label = "📋 plan generated" & (if txt.len > 0: " — " & shorten(txt, 90) else: "")
      of "planApproved":
        label = "👍 plan approved"
      of "sessionCompleted":
        label = "✅ completed"
      of "sessionStateChanged":
        label = "🔄 state " & shorten(txt, 60)
      of "agentMessaged":
        label = "💬 " & shorten(txt, 90)
      of "userMessaged":
        label = "👤 " & shorten(txt, 90)
      of "agentUsedTool":
        label = "🔧 tool: " & shorten(txt, 80)
      of "sessionCancelled":
        label = "✋ cancelled"
      break
  if label.len == 0:
    label = "activity"
  "  " & t & "  [" & origin & "]  " & label

proc activityStream*(acts: JsonNode): string =
  if acts.kind != JArray or acts.len == 0: return "  (no activities yet)"
  var lines: seq[string]
  for a in acts:
    lines.add(activityLine(a))
  lines.join("\n")

# ---------------------------------------------------------------------------
# Command implementations
# ---------------------------------------------------------------------------
proc cmdCheck(req: RequestFn, maskedKey: string) =
  let body = req("GET", "/sources?pageSize=1", nil)
  let j = parseOrErr(body)   # raises on error
  echo "✅ Jules API key valid (masked: " & maskedKey & ")"

proc cmdSpawn(req: RequestFn, repo, prompt: string, createPr: bool) =
  if createPr:
    echo "spawning + PR on " & repo & "…"
  else:
    echo "spawning on " & repo & "…"

  var obj = newJObject()
  obj["prompt"] = %prompt
  obj["sourceContext"] = %*{
    "source": "sources/github/" & repo,
    "githubRepoContext": {"startingBranch": "main"}
  }
  obj["title"] = %(if prompt.len > 60: prompt[0 ..< 60] else: prompt)
  if createPr:
    obj["automationMode"] = %"AUTO_CREATE_PR"

  let body = req("POST", "/sessions", obj)
  let j = parseOrErr(body)
  let id = j{"id"}.getStr("")
  addJob(id, repo, prompt)
  echo "  session " & id & "  →  " & j{"url"}.getStr("")
  echo "  queued. watch with:  jules watch " & id

proc cmdQueue(req: RequestFn) =
  let jobs = loadQueue()
  if jobs.len == 0:
    echo "  queue is empty. spawn with:  jules spawn <repo> \"<prompt>\""
    return
  for j in jobs:
    let body = req("GET", "/sessions/" & j.id, nil)
    var sess = newJObject()
    try: sess = parseJson(body)
    except: discard
    let state = sess{"state"}.getStr("?")
    var prs = extractPrs(sess)
    let line = "  " & stateIcon(state) & " " & j.id & "  " &
               shorten(j.prompt) &
               (if prs.len > 0: "  → " & prs[0] else: "")
    echo line

proc cmdStatus(req: RequestFn, id: string) =
  let j = parseOrErr(req("GET", "/sessions/" & id, nil))
  echo "  id:      " & j{"id"}.getStr("")
  echo "  title:   " & j{"title"}.getStr("")
  echo "  state:   " & stateIcon(j{"state"}.getStr("")) & "  " & j{"state"}.getStr("")
  let created = j{"createTime"}.getStr("")
  if created.len > 0: echo "  created: " & niceTime(created)
  let url = j{"url"}.getStr("")
  if url.len > 0: echo "  url:     " & url
  for pr in extractPrs(j):
    echo "  pr:      " & pr
  echo ""
  let acts = parseOrErr(req("GET", "/sessions/" & id & "/activities?pageSize=12", nil))
  echo activityStream(acts{"activities"})

proc cmdActivities(req: RequestFn, id: string, limit: int) =
  let j = parseOrErr(req("GET", "/sessions/" & id & "/activities?pageSize=" & $limit, nil))
  echo activityStream(j{"activities"})

proc cmdWatch(req: RequestFn, idOrNil: string, pollSec: int) =
  ## Poll the given session (or the most recent queued one) until it leaves the
  ## running state, printing new activities as they appear.
  var id = idOrNil
  if id.len == 0:
    let jobs = loadQueue()
    if jobs.len == 0:
      echo "  no queued jobs and no id given. spawn one or pass <id>."
      quit(0)
    id = jobs[^1].id

  echo "watching " & id & " (Ctrl-C to stop watching; the agent keeps going)"
  var seen = newSeq[bool]()
  var done = false
  var st = ""
  while not done:
    st = ""
    try:
      let j = parseOrErr(req("GET", "/sessions/" & id, nil))
      st = j{"state"}.getStr("")
      let actsJson = parseOrErr(req("GET", "/sessions/" & id & "/activities?pageSize=30", nil))
      let acts = actsJson{"activities"}
      if not acts.isNil and acts.kind == JArray:
        for i in 0 ..< acts.len:
          let a = acts[i]
          if i >= seen.len:
            seen.add(true)
            echo activityLine(a)
          else:
            seen[i] = true
    except CatchableError as e:
      echo "  (poll error: " & e.msg & ")"
      st = ""

    done = st.len > 0 and st.toLowerAscii() notin ["scheduled", "queued", "running", "active"]
    if not done:
      sleep(pollSec * 1000)

  echo ""
  echo "📦 session " & id & " finished (state: " & st & ")"
  let fin = parseOrErr(req("GET", "/sessions/" & id, nil))
  for pr in extractPrs(fin):
    echo "  PR: " & pr

proc cmdPrs(req: RequestFn, apiSessions: JsonNode) =
  ## List queued jobs that have a PR, plus any API session with a PR.
  var seen = initTable[string, bool]()
  for j in loadQueue():
    try:
      let jj = parseOrErr(req("GET", "/sessions/" & j.id, nil))
      for pr in extractPrs(jj):
        if pr notin seen:
          seen[pr] = true
          echo "  " & stateIcon(jj{"state"}.getStr("")) & " " & j.id &
               "  " & shorten(j.prompt) & "  → " & pr
    except CatchableError:
      discard
  # also scan the API's recent sessions so PRs from any source show up
  for s in apiSessions:
    if s.kind != JObject: continue
    for pr in extractPrs(s):
      if pr notin seen:
        seen[pr] = true
        echo "  " & stateIcon(s{"state"}.getStr("")) & "  " & pr

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
const Help = """
jules — spawn and watch Jules coding agents.

Usage:
  jules check                          validate the API key (masked)
  jules spawn <repo> "<prompt>" [--pr] create a session + queue it
  jules queue                          list queued jobs (icon + id + PR)
  jules status <id>                    one session: state, PR, recent activity
  jules watch [id]                     poll until done, streaming activity
  jules activities <id> [--limit N]    printable activity stream
  jules prs                            pull requests across queued/completed jobs
  jules sessions                       recent API sessions
  jules send <id> "<msg>"              message the agent
  jules approve <id>                   approve a pending plan
  jules archive-all [--limit N]        archive every non-archived session
  jules help                           this help

The API key comes from $JULES_API_KEY or .env (JULES_API_KEY=...) and is
never printed. `spawn` records the job in ./.jules.json.
"""

proc main() =
  if paramCount() == 0:
    echo Help
    quit(0)
  let cmd = paramStr(1)
  if cmd in ["help", "--help", "-h"]:
    echo Help
    quit(0)

  let key = resolveKey()
  if key.len == 0:
    stderr.writeLine("ERROR: JULES_API_KEY not found. Set it in .env or export it.")
    quit(1)
  let req = realRequest(key)
  let masked = key[0 ..< min(4, key.len)] & "…" & key[max(0, key.len-4) .. ^1]

  case cmd
  of "check":
    cmdCheck(req, masked)
  of "spawn":
    if paramCount() < 3:
      echo "usage: jules spawn <repo> \"<prompt>\" [--pr]"
      quit(1)
    let repo = paramStr(2)
    var prompt = ""
    for i in 3 .. paramCount():
      if paramStr(i) == "--pr": continue
      if prompt.len > 0: prompt.add(" ")
      prompt.add(paramStr(i))
    var createPr = false
    for i in 3 .. paramCount():
      if paramStr(i) == "--pr": createPr = true
    cmdSpawn(req, repo, prompt, createPr)
  of "queue":
    cmdQueue(req)
  of "status":
    if paramCount() < 2:
      echo "usage: jules status <id>"; quit(1)
    cmdStatus(req, paramStr(2))
  of "watch":
    var id = ""
    var pollSec = 20
    var i = 2
    while i <= paramCount():
      if paramStr(i) == "--interval" and i < paramCount():
        pollSec = parseInt(paramStr(i+1)); inc i
      elif not paramStr(i).startsWith("-"):
        id = paramStr(i)
      inc i
    cmdWatch(req, id, pollSec)
  of "activities":
    var id = ""
    var limit = 30
    var i = 2
    while i <= paramCount():
      if paramStr(i) == "--limit" and i < paramCount():
        limit = parseInt(paramStr(i+1)); inc i
      else: id = paramStr(i)
      inc i
    if id.len == 0:
      echo "usage: jules activities <id>"; quit(1)
    cmdActivities(req, id, limit)
  of "prs":
    let sessions = parseOrErr(req("GET", "/sessions?pageSize=20", nil)){"sessions"}
    cmdPrs(req, sessions)
  of "sessions":
    let j = parseOrErr(req("GET", "/sessions?pageSize=20", nil))
    echo sessionTable(j{"sessions"})
  of "send":
    if paramCount() < 3:
      echo "usage: jules send <id> \"<message>\""; quit(1)
    let id = paramStr(2)
    var msg = ""
    for i in 3 .. paramCount():
      if msg.len > 0: msg.add(" ")
      msg.add(paramStr(i))
    let body = parseOrErr(req("POST", "/sessions/" & id & ":sendMessage",
                              %*{"prompt": msg}))
    echo "sent. poll with: jules activities " & id
  of "approve":
    if paramCount() < 2:
      echo "usage: jules approve <id>"; quit(1)
    discard parseOrErr(req("POST", "/sessions/" & paramStr(2) & ":approvePlan", nil))
    echo "plan approved for " & paramStr(2)
  of "archive-all":
    var limit = 100
    var i = 2
    while i <= paramCount():
      if paramStr(i) == "--limit" and i < paramCount():
        limit = parseInt(paramStr(i+1)); inc i
      inc i
    var token = ""
    var archived = 0
    while true:
      let pageUrl = "/sessions?pageSize=" & $limit &
                    (if token.len > 0: "&pageToken=" & token else: "")
      let page = parseOrErr(req("GET", pageUrl, nil))
      for s in page{"sessions"}:
        if s.kind != JObject: continue
        let sid = s{"id"}.getStr("")
        if s{"archived"}.getBool(false): continue
        discard req("POST", "/sessions/" & sid & ":archive", nil)
        echo "  archived " & sid
        inc archived
      token = page{"nextPageToken"}.getStr("")
      if token.len == 0: break
    echo "done: " & $archived & " archived"
  else:
    echo "unknown command: " & cmd & "\n"
    echo Help
    quit(1)

when isMainModule:
  main()