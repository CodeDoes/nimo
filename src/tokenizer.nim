import std/[strutils, os]

type
  TrieNode* = ref object
    children*: array[256, TrieNode]
    tokenId*: int

  WorldTokenizer* = ref object
    root*: TrieNode
    indexToToken*: seq[string]

proc newTrieNode*(): TrieNode =
  TrieNode(tokenId: -1)

proc addToken*(root: TrieNode, tokenBytes: string, tokenId: int) =
  var curr = root
  for b in tokenBytes:
    let idx = b.uint8
    if curr.children[idx] == nil:
      curr.children[idx] = newTrieNode()
    curr = curr.children[idx]
  curr.tokenId = tokenId

proc encodeUtf8Codepoint(cp: int, res: var string) =
  if cp <= 0x7F:
    res.add(char(cp))
  elif cp <= 0x7FF:
    res.add(char(0xC0 or (cp shr 6)))
    res.add(char(0x80 or (cp and 0x3F)))
  elif cp <= 0xFFFF:
    res.add(char(0xE0 or (cp shr 12)))
    res.add(char(0x80 or ((cp shr 6) and 0x3F)))
    res.add(char(0x80 or (cp and 0x3F)))
  else:
    res.add(char(0xF0 or (cp shr 18)))
    res.add(char(0x80 or ((cp shr 12) and 0x3F)))
    res.add(char(0x80 or ((cp shr 6) and 0x3F)))
    res.add(char(0x80 or (cp and 0x3F)))

proc parseHex(s: string): int =
  var val = 0
  for c in s:
    val = val shl 4
    if c >= '0' and c <= '9':
      val += ord(c) - ord('0')
    elif c >= 'a' and c <= 'f':
      val += ord(c) - ord('a') + 10
    elif c >= 'A' and c <= 'F':
      val += ord(c) - ord('A') + 10
  return val

proc parseVocabLine*(line: string, idx: var int, tokenBytes: var string, expLen: var int) =
  let space1 = line.find(' ')
  let lastSpace = line.rfind(' ')
  if space1 < 0 or lastSpace <= space1:
    raise newException(ValueError, "Invalid vocab line format: " & line)

  idx = parseInt(line[0 ..< space1])
  expLen = parseInt(line[lastSpace + 1 .. ^1])

  var literal = line[space1 + 1 ..< lastSpace].strip()
  var isBytes = false
  if literal.startsWith("b'") or literal.startsWith("b\""):
    isBytes = true
    literal = literal[1 .. ^1]

  if literal.len < 2:
    return

  let inner = literal[1 .. ^2]
  tokenBytes = ""

  var i = 0
  while i < inner.len:
    if inner[i] == '\\':
      inc i
      if i >= inner.len: break
      let c = inner[i]
      case c
      of 'x':
        if i + 2 < inner.len:
          let hexVal = parseHex(inner[i + 1 .. i + 2])
          if isBytes:
            tokenBytes.add(char(hexVal))
          else:
            encodeUtf8Codepoint(hexVal, tokenBytes)
          i += 2
      of 'u':
        if i + 4 < inner.len:
          let val = parseHex(inner[i + 1 .. i + 4])
          encodeUtf8Codepoint(val, tokenBytes)
          i += 4
      of 'U':
        if i + 8 < inner.len:
          let val = parseHex(inner[i + 1 .. i + 8])
          encodeUtf8Codepoint(val, tokenBytes)
          i += 8
      of '\\': tokenBytes.add('\\')
      of '\'': tokenBytes.add('\'')
      of '"': tokenBytes.add('"')
      of 'n': tokenBytes.add('\n')
      of 'r': tokenBytes.add('\r')
      of 't': tokenBytes.add('\t')
      of 'b': tokenBytes.add('\b')
      of 'f': tokenBytes.add('\f')
      of 'a': tokenBytes.add('\a')
      of 'v': tokenBytes.add('\v')
      else:
        tokenBytes.add(c)
    else:
      tokenBytes.add(inner[i])
    inc i

proc loadWorldTokenizer*(vocabPath: string): WorldTokenizer =
  if not fileExists(vocabPath):
    raise newException(IOError, "Vocab file not found at: " & vocabPath)

  let tok = WorldTokenizer(
    root: newTrieNode(),
    indexToToken: newSeq[string](65537)
  )

  let f = open(vocabPath, fmRead)
  defer: f.close()

  var line = ""
  var idx = 0
  var tokenBytes = ""
  var expLen = 0

  while f.readLine(line):
    if line.len == 0: continue
    parseVocabLine(line, idx, tokenBytes, expLen)
    if idx >= tok.indexToToken.len:
      tok.indexToToken.setLen(idx + 1000)
    tok.indexToToken[idx] = tokenBytes
    tok.root.addToken(tokenBytes, idx)

  return tok

proc encode*(tokenizer: WorldTokenizer, text: string): seq[uint32] =
  var idx = 0
  let n = text.len
  while idx < n:
    var curr = idx
    var node = tokenizer.root
    var bestIdx = -1
    var bestToken = -1

    while curr < n:
      let b = text[curr].uint8
      let child = node.children[b]
      if child == nil:
        break
      node = child
      inc curr
      if node.tokenId >= 0:
        bestIdx = curr
        bestToken = node.tokenId

    if bestToken >= 0:
      result.add(bestToken.uint32)
      idx = bestIdx
    else:
      inc idx

  # RWKV Chat standard: normalize trailing double EOL token (535 -> [187, 187])
  if result.len > 0 and result[^1] == 535u32:
    result.setLen(result.len - 1)
    result.add(187u32)
    result.add(187u32)

proc decodeToken*(tokenizer: WorldTokenizer, token: uint32): string =
  if token.int < tokenizer.indexToToken.len:
    return tokenizer.indexToToken[token.int]
  return ""

proc decode*(tokenizer: WorldTokenizer, tokens: openArray[uint32]): string =
  for t in tokens:
    if t.int < tokenizer.indexToToken.len:
      result.add(tokenizer.indexToToken[t.int])
