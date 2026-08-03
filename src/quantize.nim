## RWKV Quantization CLI
## Usage: nimo quantize <input.bin> <format> <output.bin>
## Example: nimo quantize ./models/rwkv7-g1i-2.9b-20260729-ctx16384-f16.bin q4k ./models/rwkv7-g1i-2.9b-20260729-ctx16384-q4k.bin

import std/[os, strutils, strformat, times]
import cli, rwkv/model/header, rwkv/quant/cache, rwkv

proc quantizeCmd(args: seq[string]) =
  if args.len < 3:
    echo """nimo quantize <input.bin> <format> <output.bin>

Convert a raw FP16/FP32 model to a quantized format.

Arguments:
  input       Source model file (FP16 or FP32)
  format      Target quantization format (Q4_0, Q4_K, Q5_0, Q5_K, Q6_K, Q8_0, etc.)
  output      Destination model file

Example:
  nimo quantize ./models/rwkv7-g1i-2.9b-f16.bin Q4_K ./models/rwkv7-g1i-2.9b-q4k.bin
"""
    quit(1)

  let inputPath = args[0]
  let format = args[1].strip().toUpperAscii()
  let outputPath = args[2]

  if not fileExists(inputPath):
    printError &"Input model not found: {inputPath}"
    quit(1)

  let h = readModelHeader(inputPath)
  if not isValidHeader(h):
    printError &"Invalid model header in: {inputPath}"
    quit(1)

  if isQuantized(h):
    printError &"Input model is already quantized (dtype={h.dataType}). Use a raw FP16/FP32 model."
    quit(1)

  printInfo &"Input:    {inputPath}"
  printInfo &"Format:   {format}"
  printInfo &"Output:   {outputPath}"
  printInfo &"Input dtype: FP{(if h.dataType == DtypeFP32: \"32\" else: \"16\")}"
  printInfo &"Layers:   {h.nLayer}, Embed:  {h.nEmbed}, Vocab: {h.nVocab}"
  echo SepThin

  when defined(harnessOffline):
    printError "Quantization not available in offline mode."
    quit(1)

  try:
    bindBackend("rwkv.cpp/librwkv.so")
  except RwkvException as e:
    printError &"Failed to load backend: {e.msg}"
    quit(1)

  createDir(parentDir(outputPath))
  setPrintErrors(nil, true)

  echo "[quant] Converting..."
  let t0 = cpuTime()
  let success = quantizeModelFile(inputPath, outputPath, format)
  let elapsed = cpuTime() - t0

  if not success:
    let errCode = getLastError(nil)
    printError &"Quantization failed (error {errCode}): " & decodeError(errCode)
    quit(1)

  let inSize = getFileSize(inputPath) div (1024 * 1024)
  let outSize = getFileSize(outputPath) div (1024 * 1024)
  let ratio = float(outSize) / float(inSize) * 100.0

  printSuccess &"Quantized {inputPath} -> {outputPath}"
  printSuccess &"Size: {inSize} MiB -> {outSize} MiB ({ratio:.1f}%)"
  printSuccess &"Time: {elapsed:.2f}s"

when isMainModule:
  var args = newSeq[string]()
  for i in 1 .. paramCount():
    args.add(paramStr(i))
  quantizeCmd(args)
