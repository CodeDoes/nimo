## rwkv/quant/cache.nim — Quant cache manager.
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
import ../../config, rwkv/model/header
when not defined(harnessOffline):
  import ../../rwkv

type
  ModelCache* = object
    cacheDir*: string

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
