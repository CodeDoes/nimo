## Session Branching for NIMO
## Implements RFC 1000: alternative conversation paths.

import std/[json, os, times, strformat, tables]
import ./session_manager

type
  Branch* = ref object
    id*: string
    parentId*: string
    timestamp*: string
    messages*: seq[Message]

  SessionBranch* = ref object
    sessions*: seq[string]      # session IDs
    branches*: seq[Branch]      # actual branch data
    activeBranch*: int

proc newSessionBranch*(): SessionBranch =
  ## Creates a new session branch manager.
  result = SessionBranch.new()
  result.activeBranch = 0

proc addBranch*(s: var SessionBranch, parentId: string): string =
  ## Creates a new branch from a parent message ID.
  let branchId = "branch_" & now().format("yyyyMMddHHmmss") & "_" & $s.branches.len
  s.branches.add(Branch(
    id: branchId,
    parentId: parentId,
    timestamp: nowStr(),
    messages: @[]
  ))
  return branchId

proc switchBranch*(s: var SessionBranch, branchId: string): bool =
  ## Switches to a branch by ID. Returns false if not found.
  for i in 0 ..< s.branches.len:
    if s.branches[i].id == branchId:
      s.activeBranch = i
      return true
  return false

proc getBranch*(s: SessionBranch, index: int): Branch =
  ## Gets a branch by index.
  if index < 0 or index >= s.branches.len:
    raise newException(IndexError, "Branch index out of range: " & $index)
  return s.branches[index]

proc getCurrentBranch*(s: SessionBranch): Branch =
  ## Gets the currently active branch.
  if s.branches.len == 0:
    raise newException(IndexError, "No branches exist")
  return s.branches[s.activeBranch]

proc listBranches*(s: SessionBranch): seq[string] =
  ## Lists all branch IDs with timestamps.
  result = @[]
  for b in s.branches:
    result.add(b.id & " (" & b.timestamp & ")")

proc addMessageToBranch*(s: var SessionBranch, msg: Message) =
  ## Adds a message to the current branch.
  if s.branches.len > 0:
    s.branches[s.activeBranch].messages.add(msg)

proc saveBranch*(s: SessionBranch, path: string) =
  ## Saves branch data to a JSON file, including the branch messages.
  let dir = parentDir(path)
  if dir.len > 0 and dir != ".":
    createDir(dir)
  var j = newJObject()
  j["activeBranch"] = %s.activeBranch
  var branches = newJArray()
  for b in s.branches:
    var bj = newJObject()
    bj["id"] = %b.id
    bj["parentId"] = %b.parentId
    bj["timestamp"] = %b.timestamp

    var msgsJ = newJArray()
    for m in b.messages:
      msgsJ.add(messageToJson(m))
    bj["messages"] = msgsJ

    branches.add(bj)
  j["branches"] = branches
  writeFile(path, $j)

proc loadBranch*(s: var SessionBranch, path: string): bool =
  ## Loads branch data from a JSON file, including the branch messages.
  if not fileExists(path):
    return false
  try:
    let j = parseJson(readFile(path))
    s.activeBranch = j["activeBranch"].getInt(0)
    s.branches = @[]
    for bj in j["branches"]:
      var msgs: seq[Message] = @[]
      if "messages" in bj and bj["messages"].kind == JArray:
        for mj in bj["messages"]:
          msgs.add(messageFromJson(mj))
      let b = Branch(
        id: bj["id"].str,
        parentId: bj["parentId"].str,
        timestamp: bj["timestamp"].str,
        messages: msgs
      )
      s.branches.add(b)
    return true
  except:
    return false

proc mergeBranch*(s: var Session, branchId: string): string =
  ## Merges a branch back into the main session (fallback stub signature).
  return "Branch merge requires SessionBranch data"

proc mergeBranch*(s: var Session, sb: SessionBranch, branchId: string): string =
  ## Merges a branch back into the main session, mapping message IDs to prevent clashes.
  var foundBranch: Branch = nil
  for b in sb.branches:
    if b.id == branchId:
      foundBranch = b
      break
  if foundBranch == nil:
    return "Error: Branch " & branchId & " not found"

  if foundBranch.messages.len == 0:
    return "Branch " & branchId & " is empty, nothing to merge"

  var idMap = initTable[string, string]()
  var mergedCount = 0
  for msg in foundBranch.messages:
    let oldId = msg.id
    let oldParentId = msg.parentId
    let newParentId = if oldParentId == "" or oldParentId == foundBranch.parentId:
                        foundBranch.parentId
                      elif oldParentId in idMap:
                        idMap[oldParentId]
                      else:
                        oldParentId
    let newId = s.addMessage(msg.role, msg.content, newParentId)
    idMap[oldId] = newId
    inc mergedCount

  return "Successfully merged " & $mergedCount & " messages from branch " & branchId & " into session"

proc formatBranchList*(s: SessionBranch): string =
  ## Formats branch list for display.
  result = "Branches:\n"
  if s.branches.len == 0:
    result.add("  (no branches)")
  else:
    for i in 0 ..< s.branches.len:
      let marker = if i == s.activeBranch: ">" else: " "
      result.add(&"  {marker} {s.branches[i].id}\n")
      result.add(&"     Parent: {s.branches[i].parentId}\n")
      result.add(&"     Time: {s.branches[i].timestamp}\n")
      result.add(&"     Messages: {s.branches[i].messages.len}\n")
