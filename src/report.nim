## Report Generation for NIMO
## Generates reports from sessions, pipelines, and workspaces.

import std/[json, strutils, os, times, tables, strformat]
import ./session_manager, ./workspace, ./story

type
  ReportType* = enum
    rtSession, rtPipeline, rtWorkspace, rtStory

  Report* = ref object
    id*: string
    timestamp*: string
    reportType*: ReportType
    title*: string
    content*: string
    metadata*: Table[string, string]
    relatedItems*: seq[string]

proc newReport*(reportType: ReportType, title: string): Report =
  result = Report.new()
  result.id = "report_" & now().format("yyyyMMddHHmmss")
  result.timestamp = nowStr()
  result.reportType = reportType
  result.title = title
  result.metadata = initTable[string, string]()
  result.relatedItems = @[]

proc addMetadata*(r: var Report, key: string, value: string) =
  r.metadata[key] = value

proc addRelatedItem*(r: var Report, itemId: string) =
  r.relatedItems.add(itemId)

proc generateSessionReport*(session: Session): Report =
  ## Generates a report from a session.
  result = newReport(rtSession, "Session Report: " & session.id)
  result.addMetadata("messageCount", $session.messages.len)
  result.addMetadata("branchCount", "0")  # TODO: count branches
  
  var content = "## Session Report\n\n"
  content.add("**Session ID:** " & session.id & "\n")
  content.add("**Timestamp:** " & session.timestamp & "\n")
  content.add("**CWD:** " & session.cwd & "\n\n")
  content.add("### Messages\n\n")
  
  for msg in session.messages:
    content.add(&"- **{msg.id}** ({msg.role}): {msg.content[0].text[0 ..< min(50, msg.content[0].text.len)]}...\n")
  
  result.content = content

proc generateWorkspaceReport*(ws: Workspace): Report =
  ## Generates a report from a workspace.
  result = newReport(rtWorkspace, "Workspace Report: " & ws.name)
  
  var content = "## Workspace Report\n\n"
  content.add("**Workspace:** " & ws.name & "\n")
  content.add("**Path:** " & ws.path & "\n")
  content.add("**Created:** " & ws.created & "\n\n")
  
  # Count items in each directory
  for dir in ["wiki", "chapters", "sessions"]:
    let dirPath = ws.path / dir
    var count = 0
    if dirExists(dirPath):
      for _ in walkDir(dirPath): inc count
    content.add(&"**{dir}/**: {count} items\n")
  
  result.content = content

proc generateStoryReport*(ws: Workspace, chapterCount: int): Report =
  ## Generates a report from a story workspace.
  result = newReport(rtStory, "Story Report: " & ws.name)
  
  var content = "## Story Report\n\n"
  content.add("**Workspace:** " & ws.name & "\n")
  content.add(&"**Chapters Generated:** {chapterCount}\n\n")
  
  # List chapters
  let chapters = ws.listChapters()
  content.add("### Chapters\n\n")
  for ch in chapters:
    content.add(&"- {ch}\n")
  
  result.content = content

proc saveReport*(r: Report, path: string) =
  ## Saves report to JSON file.
  let dir = parentDir(path)
  if dir.len > 0 and dir != ".":
    createDir(dir)
  
  var j = newJObject()
  j["id"] = %r.id
  j["timestamp"] = %r.timestamp
  j["reportType"] = %($r.reportType)
  j["title"] = %r.title
  j["content"] = %r.content
  
  var meta = newJObject()
  for k, v in r.metadata.pairs:
    meta[k] = %v
  j["metadata"] = meta
  
  var related = newJArray()
  for item in r.relatedItems:
    related.add(%item)
  j["relatedItems"] = related
  
  writeFile(path, $j)

proc loadReport*(path: string): Report =
  ## Loads report from JSON file.
  if not fileExists(path):
    raise newException(IOError, "Report file not found: " & path)
  
  let j = parseJson(readFile(path))
  result = Report(
    id: j["id"].str,
    timestamp: j["timestamp"].str,
    reportType: parseEnum[ReportType](j["reportType"].str),
    title: j["title"].str,
    content: j["content"].str,
    metadata: initTable[string, string](),
    relatedItems: @[]
  )
  
  if "metadata" in j:
    for k, v in j["metadata"].pairs:
      result.metadata[k] = v.str
  
  if "relatedItems" in j:
    for item in j["relatedItems"]:
      result.relatedItems.add(item.str)

proc formatReport*(r: Report): string =
  ## Formats report for display.
  var result = "=== " & r.title & " ===\n"
  result.add(&"\nType: {r.reportType}\n")
  result.add(&"ID: {r.id}\n")
  result.add(&"Timestamp: {r.timestamp}\n")
  result.add("\n" & r.content)
  return result
