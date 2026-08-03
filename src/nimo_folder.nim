## NIMO Application Folder Management
## Creates and manages the .nimo/ application folder.

import std/[os, strutils, times, json]
import ./config

const
  NimoDirName = ".nimo"
  NimoConfigName = "config.json"
  NimoStateDir = "state"
  NimoCacheDir = "cache"
  NimoLogsDir = "logs"
  NimoSessionsDir = "sessions"
  NimoPipelinesDir = "pipelines"

type
  NimoFolder* = ref object
    path*: string
    created*: string

proc newNimoFolder*(basePath: string = "."): NimoFolder =
  result = NimoFolder.new()
  result.path = basePath / NimoDirName
  result.created = now().format("yyyy-MM-dd HH:mm:ss")
  
  createDir(result.path)
  createDir(result.path / NimoStateDir)
  createDir(result.path / NimoCacheDir)
  createDir(result.path / NimoLogsDir)
  createDir(result.path / NimoSessionsDir)
  createDir(result.path / NimoPipelinesDir)
  
  let configContent = "{\"version\": \"1.0\", \"created\": \"" & result.created & "\", \"basePath\": \"" & basePath & "\"}"
  writeFile(result.path / NimoConfigName, configContent)

proc getNimoFolder*(basePath: string = "."): NimoFolder =
  let path = basePath / NimoDirName
  if dirExists(path):
    result = NimoFolder(path: path, created: "")
  else:
    result = newNimoFolder(basePath)

proc getStatePath*(nimo: NimoFolder, name: string): string =
  return nimo.path / NimoStateDir / name

proc getCachePath*(nimo: NimoFolder, name: string): string =
  return nimo.path / NimoCacheDir / name

proc getLogPath*(nimo: NimoFolder, name: string): string =
  return nimo.path / NimoLogsDir / name

proc getSessionPath*(nimo: NimoFolder, name: string): string =
  return nimo.path / NimoSessionsDir / name

proc getPipelinePath*(nimo: NimoFolder, name: string): string =
  return nimo.path / NimoPipelinesDir / name

proc formatNimoStructure*(nimo: NimoFolder): string =
  var result = "=== .nimo/ Structure ===\n\n"
  result.add("Path: " & nimo.path & "\n")
  result.add("Created: " & nimo.created & "\n\n")
  result.add("Directories:\n")
  for dir in [NimoStateDir, NimoCacheDir, NimoLogsDir, NimoSessionsDir, NimoPipelinesDir]:
    let fullDir = nimo.path / dir
    var count = 0
    if dirExists(fullDir):
      for _ in walkDir(fullDir): inc count
    result.add("  " & dir & "/ (" & $count & " files)\n")
  return result
