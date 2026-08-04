## Story Pipeline for NIMO
## Implements RFC 3200: multi-chapter story generation with wiki context.

import std/[json, strutils, os, times, strformat]
import ./session_manager, ./config, ./workspace
import ./program

type
  StoryQuality* = enum
    sqPass, sqFail, sqNeedsRevision

  ChapterValidation* = object
    chapter*: int
    title*: string
    wordCount*: int
    paragraphCount*: int
    repeatingSegments*: int
    quality*: StoryQuality
    issues*: seq[string]

  CritiqueResult* = object
    chapter*: int
    score*: float
    strengths*: seq[string]
    weaknesses*: seq[string]
    suggestions*: seq[string]
    shouldRevise*: bool

const
  DefaultMinChapterWords* = 500
  DefaultMinParagraphs* = 5
  DefaultMaxRepeats* = 3

proc countWords*(s: string): int =
  ## Counts words in a string.
  var count = 0
  var inWord = false
  for c in s:
    if c.isAlphaNumeric() or c == '_' or c == '\'':
      if not inWord:
        inc count
        inWord = true
    else:
      inWord = false
  return count

proc countLines*(s: string): int =
  ## Counts non-empty lines (paragraphs).
  var count = 0
  for line in s.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      inc count
  return count

proc validateChapter*(content: string, minWords: int = DefaultMinChapterWords,
                      minParagraphs: int = DefaultMinParagraphs,
                      maxRepeats: int = DefaultMaxRepeats): ChapterValidation =
  ## Validates chapter quality against classic writing criteria.
  result.chapter = 0
  result.title = ""
  result.wordCount = content.countWords()
  result.paragraphCount = content.countLines()
  result.repeatingSegments = 0
  result.issues = @[]
  
  # Extract title from first line
  let lines = content.strip().splitLines()
  if lines.len > 0:
    result.title = lines[0].replace("#", "").strip()
  
  # Check for repeating segments
  let words = content.strip().splitWhitespace()
  for i in 0 ..< max(words.len - maxRepeats * 3, 0):
    var repeatCount = 0
    for j in 1 ..< maxRepeats:
      if i + j * 3 < words.len:
        let seq1 = words[i ..< i + 3].join(" ")
        let seq2 = words[i + j * 3 ..< i + j * 3 + 3].join(" ")
        if seq1 == seq2:
          inc repeatCount
    if repeatCount >= maxRepeats:
      inc result.repeatingSegments
  
  # Determine quality
  if result.wordCount < minWords:
    result.issues.add("Word count too low: " & $result.wordCount & " < " & $minWords)
  if result.paragraphCount < minParagraphs:
    result.issues.add("Paragraph count too low: " & $result.paragraphCount & " < " & $minParagraphs)
  if result.repeatingSegments > 0:
    result.issues.add("Found " & $result.repeatingSegments & " repeating segments")
  
  if result.issues.len == 0:
    result.quality = sqPass
  else:
    result.quality = sqFail

proc critiqueChapter*(content: string, chapterNum: int): CritiqueResult =
  ## Generates critique for a chapter.
  result.chapter = chapterNum
  result.score = 7.0
  result.strengths = @[]
  result.weaknesses = @[]
  result.suggestions = @[]
  result.shouldRevise = false
  
  let validation = validateChapter(content)
  
  case validation.quality
  of sqPass:
    result.score = 8.5
    result.strengths.add("Meets minimum word count")
    result.strengths.add("Good paragraph structure")
  of sqFail:
    result.score = 5.0
    result.shouldRevise = true
    for issue in validation.issues:
      result.weaknesses.add(issue)
      result.suggestions.add("Fix: " & issue)
  of sqNeedsRevision:
    result.score = 6.5
    result.shouldRevise = true

proc generateWikiEntry*(session: var Session, characterName: string, traits: string): string =
  ## Generates a wiki entry for a character.
  let prompt = "Create a detailed character wiki entry for:\n\nName: " & characterName & 
               "\nTraits: " & traits & 
               "\n\nInclude: Physical description, Personality traits, Background, Motivations, Relationships, Key abilities/skills\n\nFormat as markdown with clear sections."
  return session.generateTurn(prompt)

proc generateChapter*(session: var Session, chapterNum: int, title: string,
                      wikiContext: string, previousRecap: string = ""): string =
  ## Generates a chapter with wiki context.
  var prompt = "Write Chapter " & $chapterNum & ": " & title & "\n\n"
  if wikiContext.len > 0:
    prompt.add("Character/World Context:\n" & wikiContext & "\n\n")
  if previousRecap.len > 0:
    prompt.add("Previous Chapter Summary:\n" & previousRecap & "\n\n")
  
  prompt.add("Write a compelling chapter that:\n- Advances the plot\n- Develops characters\n- Maintains consistent tone\n- Includes dialogue and action\n- Ends with a hook for the next chapter\n\nAim for 500+ words with 5+ paragraphs.")
  
  return session.generateTurn(prompt)

proc summarizeChapter*(session: var Session, content: string): string =
  ## Summarizes a chapter for continuity.
  let prompt = "Summarize the following chapter in 3-5 bullet points, focusing on:\n- Key plot events\n- Character developments\n- Important revelations\n- Setup for next chapter\n\nChapter content:\n" & content
  return session.generateTurn(prompt)

proc generateOutline*(session: var Session, premise: string): string =
  ## Generates a story outline.
  let prompt = "Create a detailed story outline for:\n\nPremise: " & premise & 
               "\n\nInclude:\n- Title\n- Logline (1-2 sentences)\n- Main characters (3-5)\n- Setting/world\n- Plot summary (beginning, middle, end)\n- Chapter outline (5-7 chapters)\n- Themes\n\nFormat as markdown."
  return session.generateTurn(prompt)

proc runStoryPipeline*(ws: Workspace, session: var Session, 
                       premise: string, maxChapters: int = 5): bool =
  ## Runs the full story pipeline with validation.
  echo "[pipeline] Generating story outline..."
  let outline = generateOutline(session, premise)
  
  let outlinePath = ws.path / "outline.md"
  writeFile(outlinePath, outline)
  echo "[pipeline] Outline saved to outline.md"
  
  echo "[pipeline] Generating chapters..."
  var previousRecap = ""
  
  for chNum in 1 .. maxChapters:
    echo "[pipeline] Generating Chapter " & $chNum & "..."
    
    # Generate chapter
    let chapterContent = generateChapter(session, chNum, 
                      "Chapter " & $chNum, "", previousRecap)
    
    # Validate
    let validation = validateChapter(chapterContent)
    echo "  [validate] Chapter " & $chNum & ": " & 
         $validation.wordCount & " words, " & 
         $validation.paragraphCount & " paragraphs, quality=" & $validation.quality
    
    if validation.quality == sqFail:
      echo "  [critique] Chapter " & $chNum & " needs revision:"
      for issue in validation.issues:
        echo "    - " & issue
      
      # Attempt revision
      echo "  [pipeline] Attempting revision..."
      let revised = generateChapter(session, chNum,
        "Chapter " & $chNum, 
        "Previous attempts failed validation. Please ensure:\n- Word count >= 500\n- Paragraph count >= 5\n- No repeating segments",
        previousRecap)
      
      let revisedValidation = validateChapter(revised)
      if revisedValidation.quality == sqPass:
        echo "  [pipeline] Revision successful"
        previousRecap = revised
      else:
        echo "  [pipeline] Revision still failing, using original"
        previousRecap = chapterContent
    else:
      previousRecap = chapterContent
    
    # Save chapter
    ws.createChapter(chNum, "Chapter " & $chNum, chapterContent)
  
  echo "[pipeline] Story generation complete"
  return true

# ---------------------------------------------------------------------------
# Plan template for story generation (RFC 3200)
# ---------------------------------------------------------------------------
proc storyPlan*(premise: string): Plan =
  ## Creates a Plan for story generation from a premise (RFC 3200 template).
  ## The plan follows: outline -> character extraction -> wiki generation ->
  ## per-chapter (outline+wiki slice -> generate) -> validate -> critique -> write.
  result = newPlan(premise)
  
  # Step 1: Generate outline
  result.addStep(generateStep("generate-outline", 
    "Create a story outline for: " & premise, "output:outline"))
  result.addStep(writeStep("save-outline", "outline.md"))
  
  # Step 2: Extract characters from outline
  result.addStep(extractStep("pull-characters", "outline", "main characters"))
  
  # Step 3: Generate wiki entries for each character (loop placeholder)
  result.addStep(generateStep("generate-wiki", 
    "Generate wiki entries for: " & premise, "output:wiki"))
  
  # Step 4-6: Per-chapter generation (outline+wiki -> generate -> validate -> write)
  for chNum in 1 .. 3:  # Default 3 chapters
    result.addStep(generateStep("draft-chapter-" & $chNum,
      "Draft Chapter " & $chNum & " for: " & premise, "output:chapter"))
    result.addStep(validateStep("gate-chapter-" & $chNum, ""))
    result.addStep(writeStep("save-chapter-" & $chNum, 
      "chapter_" & $chNum & ".md"))
  
  # Step 7: Final report
  result.addStep(reportStep("story complete"))
