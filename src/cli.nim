## CLI TUI Helpers for NIMO
## Provides banner printing and common CLI output utilities.
## The nimwave_app module uses illwave directly for its full TUI dashboard.

import std/[times, terminal]

# ── Banner / layout helpers ───────────────────────────────────────────────────

const BannerSep* = "=========================================================="
const SepThin*   = "----------------------------------------------------------"

proc printBanner*(title: string) =
  styledEcho(styleBright, fgCyan, BannerSep, " ", title, " ", BannerSep)

proc printConfig*(modelPath, vocabPath: string) =
  echo "Model path: ", modelPath
  echo "Vocab path: ", vocabPath

proc printError*(msg: string) =
  styledEcho(fgRed, msg)

proc printSuccess*(msg: string) =
  styledEcho(fgGreen, msg)

proc printInfo*(msg: string) =
  echo msg

proc printWarn*(msg: string) =
  styledEcho(fgYellow, msg)

# ── Time helper ───────────────────────────────────────────────────────────────

proc formatTimeNow*(): string = now().format("HH:mm:ss")
