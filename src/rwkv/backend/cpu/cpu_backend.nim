## CPU backend provider.
##
## The CPU "backend" runs the same rwkv.cpp engine with GPU offload disabled
## (gpuLayers=0). Validates available RAM and errors if the model won't fit.

import std/[os, strutils, strformat]
import config, rwkv/model/header, rwkv/backend/types

const
  CpuMinRamMiB* = 1024       # absolute minimum RAM required

proc cpuBackend*(): RwkvBackend =
  RwkvBackend(kind: bkCpu, name: "cpu",
              libPath: "rwkv.cpp/librwkv.so",
              defaultGpuLayers: 0)

proc checkCpuLoad*(backend: RwkvBackend, modelPath: string,
                   loadStrategy: string): string =
  ## Validates CPU load feasibility. Returns error message or "" if OK.
  if not fileExists(modelPath):
    return "Model not found: " & modelPath

  let h = readModelHeader(modelPath)
  if not isValidHeader(h):
    return "Invalid model header in: " & modelPath

  let modelMiB = modelSizeMiB(h)

  # Get system RAM
  var totalMem = 0i64
  when defined(linux):
    var f: File
    if f.open("/proc/meminfo", fmRead):
      for line in f.lines:
        if line.startsWith("MemTotal:"):
          let parts = line.splitWhitespace()
          if parts.len >= 2:
            try: totalMem = parseInt(parts[1]) * 1024  # kB -> B
            except: discard
          break
      f.close()
  elif defined(windows):
    var total, avail: int64
    if os.getWinMemoryInfo(total, avail):
      totalMem = total
  # macOS and others: skip detailed check

  let totalMiB = int(totalMem div (1024 * 1024))
  if totalMiB < CpuMinRamMiB:
    return &"Insufficient RAM: need ~{modelMiB} MiB, found {totalMiB} MiB"
  if modelMiB > totalMiB:
    return &"Model too large for available RAM: {modelMiB} MiB > {totalMiB} MiB"

  return ""  # OK
