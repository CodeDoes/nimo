## model_cache.nim — "raw -> quantize -> cache".
##
## Content-addressed, idempotent cache of quantized model artifacts.
## Given a raw FP32/FP16 model, `ensureQuantized` produces (or reuses) a
## quantized copy cached by a content signature, so re-runs skip the CPU/GPU
## cost of quantization. Mirrors rfc/8150-quantization.md.
##
## Offline-safe: every hash/key/path computation compiles and runs under
## `-d:harnessOffline`; only the actual rwkv.cpp quantizer call is gated to
## online builds.

import std/[os, strutils, times, sha1]
import ./config
when not defined(harnessOffline):
  import ./rwkv

type
  ModelHeader* = object
    magic*: uint32
    version*: uint32
    nVocab*: uint32
    nEmbed*: uint32
    nLayer*: uint32
    dataType*: uint32

  ModelCache* = object
    cacheDir*: string

const
  ModelMagic* = 0x67676d66'u32  # 24-byte header: 6 x LE u32

# rwkv.cpp data_type indexes (see rwkv_file_format.inc TYPE_*)
const
  DtypeFP32* = 0
  DtypeFP16* = 1
  FirstQuantType* = 2           # Q4_0 onwards are all quantized

proc readModelHeader*(path: string): ModelHeader =
  ## Reads the 24-byte rwkv.cpp file header straight off disk (no library load).
  result.dataType = uint32.high
  var f: File
  if not f.open(path, fmRead):
    return
  defer: f.close()
  var b: array[24, uint8]
  if f.readBytes(b, 0, 24) != 24:
    return
  template u32le(off: int): uint32 =
    uint32(b[off]) or (uint32(b[off + 1]) shl 8) or
    (uint32(b[off + 2]) shl 16) or (uint32(b[off + 3]) shl 24)
  result.magic = u32le(0)
  result.version = u32le(4)
  result.nVocab = u32le(8)
  result.nEmbed = u32le(12)
  result.nLayer = u32le(16)
  result.dataType = u32le(20)

proc isValidHeader*(h: ModelHeader): bool = h.magic == ModelMagic
proc isRawModel*(h: ModelHeader): bool = isValidHeader(h) and h.dataType < FirstQuantType
proc isQuantized*(h: ModelHeader): bool = isValidHeader(h) and h.dataType >= FirstQuantType

proc modelSignature*(path: string): string =
  ## Fast content signature: file size + mtime + first 512 bytes hashed.
  ## Hashing the whole multi-GB file each run is too slow; size/mtime/header
  ## catch any real model swap and are cheap. Good enough for a dev cache.
  if not fileExists(path):
    return ""
  let st = path.getFileInfo()
  var head = newString(512)
  var n = 0
  var f: File
  if f.open(path, fmRead):
    n = f.readBuffer(addr head[0], 512)
    f.close()
  head.setLen(n)
  $secureHash($st.size & "|" & $st.lastWriteTime.toUnix & "|" & head)

proc hashText*(s: string): string =
  ## sha1 hex of arbitrary content, used for multi-part cache keys.
  $secureHash(s)

proc initModelCache*(cacheDir: string = DefaultModelCacheDir): ModelCache =
  result.cacheDir = cacheDir

proc quantizedPath*(c: ModelCache, rawPath: string, format: string): string =
  ## Deterministic cached-path for a raw model + quant format.
  ## <cacheDir>/<sig12>-<formatLower>.bin
  let sig = modelSignature(rawPath)
  let fmt = format.toLowerAscii()
  c.cacheDir / (sig[0 ..< min(12, sig.len)] & "-" & fmt & ".bin")

proc ensureQuantized*(c: ModelCache, rawPath: string, format: string):
    tuple[path: string, cached: bool] =
  ## Returns the model to actually load:
  ## - if rawPath is already quantized, use it directly;
  ## - else if the cached <format> artifact exists, reuse it;
  ## - else quantize rawPath -> cache (online builds only).
  ##
  ## `cached` flags whether the result came from an existing artifact vs. a
  ## freshly produced one. Raises on conversion failure.
  let h = readModelHeader(rawPath)
  if isQuantized(h):
    return (rawPath, true)   # already quantized; load as-is

  let outPath = c.quantizedPath(rawPath, format)
  when not defined(harnessOffline):
    if fileExists(outPath):
      return (outPath, true)
    if format.len == 0:
      return (rawPath, true)
    createDir(c.cacheDir)
    setPrintErrors(nil, false)
    if not quantizeModelFile(rawPath, outPath, format):
      raise newException(IOError, "Quantization of '" & rawPath & "' to '" &
                         format & "' failed.")
    return (outPath, false)
  else:
    # Offline builds can't invoke the quantizer; report the would-be path.
    result.path = outPath
    result.cached = fileExists(outPath)