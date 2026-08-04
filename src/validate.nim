## validate.nim — deterministic quality gates (a pointed tool)
## Pure text validation: word counts, paragraph counts, repeating segments.
## No model, no I/O beyond the string — fully unit-testable offline.
## Used by the engine's Validate step and (Phase 4) the story pipeline.

import std/[strutils]

type
  ValidationResult* = object
    wordCount*: int
    paragraphCount*: int
    repeatingSegments*: int
    passed*: bool
    issues*: seq[string]

const
  # Named constants for punctuation chars — inline char literals like '\''
  # break isAlphaNumeric resolution in some compilers, so never inline them.
  Apostrophe = '\''
  Underscore = '_'

proc countWords*(s: string): int =
  var count = 0
  var inWord = false
  for c in s:
    if c.isAlphaNumeric() or c == Underscore or c == Apostrophe:
      if not inWord:
        inc count
        inWord = true
    else:
      inWord = false
  result = count

proc countLines*(s: string): int =
  ## Counts non-empty lines (paragraphs).
  for line in s.splitLines():
    if line.strip().len > 0:
      inc result

proc validateText*(content: string,
                   minWords: int = 500,
                   minParagraphs: int = 5,
                   maxRepeats: int = 3): ValidationResult =
  result.wordCount = content.countWords()
  result.paragraphCount = content.countLines()
  result.issues = @[]

  # repeating segments: a 3-word sequence appearing `maxRepeats`+ times (looping)
  let words = content.strip().splitWhitespace()
  var i = 0
  while i + 3 <= words.len:
    let seqStr = words[i ..< i + 3].join(" ")
    var occurrences = 1
    for j in i + 3 ..< words.len - 2:
      if words[j ..< j + 3].join(" ") == seqStr:
        inc occurrences
    if occurrences >= maxRepeats:
      inc result.repeatingSegments
      i += 3   # skip past the detected repeat so the same window isn't re-counted
    else:
      inc i

  if result.wordCount < minWords:
    result.issues.add("Word count too low: " & $result.wordCount & " < " & $minWords)
  if result.paragraphCount < minParagraphs:
    result.issues.add("Paragraph count too low: " & $result.paragraphCount & " < " & $minParagraphs)
  if result.repeatingSegments > 0:
    result.issues.add("Found " & $result.repeatingSegments & " repeating segments")

  result.passed = result.issues.len == 0