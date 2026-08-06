## Simple file-based lock for model loading
## Prevents multiple processes from loading the model simultaneously (OOM)

import std/[os, strutils, times]

const LockFileName = ".nimo/model.lock"

proc acquireModelLock*(timeoutSec: int = 30): bool =
  ## Try to acquire the model lock. Returns true if acquired, false if timeout.
  let lockPath = getCurrentDir() / LockFileName
  let startTime = epochTime()
  
  while true:
    try:
      if fileExists(lockPath):
        let lockContent = readFile(lockPath).strip()
        let lockTime = parseFloat(lockContent.split(" ")[0])
        let elapsed = epochTime() - lockTime
        if elapsed > float(timeoutSec):
          # Stale lock, remove it
          removeFile(lockPath)
          continue
        # Lock held by another process, wait
        sleep(100)
        continue
      
      # Try to acquire lock
      let pid = getCurrentProcessId()
      let timestamp = $epochTime()
      let dir = parentDir(lockPath)
      if dir.len > 0 and dir != "." and not dirExists(dir):
        createDir(dir)
      writeFile(lockPath, timestamp & " " & $pid)
      return true
    except:
      # If any error, try to remove stale lock and retry
      if fileExists(lockPath):
        removeFile(lockPath)
      sleep(100)
  
  return false

proc releaseModelLock*() =
  ## Release the model lock
  let lockPath = getCurrentDir() / LockFileName
  if fileExists(lockPath):
    removeFile(lockPath)

proc withModelLock*(body: proc(): bool): bool =
  ## Acquire lock, run body, release lock
  if not acquireModelLock():
    return false
  try:
    return body()
  finally:
    releaseModelLock()
