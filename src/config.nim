## Global Configuration and Utility Helpers for RWKV Nim

import std/[os, strutils]

const
  DefaultModelPath* = "models/rwkv7-g1h-2.9b-20260710-ctx10240-q4_0.bin"
  DefaultVocabPath* = "rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt"
  DefaultPrompt* = "User: Hi!\n\nBot: Hello! How can I help you today?"
  DefaultGenLength* = 60
  DefaultTemp* = 0.7f
  DefaultTopP* = 0.7f
  DefaultChunkSize* = 16
  DefaultThreads* = 4
  DefaultGpuLayers* = 99  # Offload all layers to GPU VRAM by default

proc resolveModelPath*(path: string): string =
  ## Automatically resolves .st / .pth / .safetensors model path candidates to matching .bin GGML model file.
  result = path
  if result.endsWith(".st") or result.endsWith(".pth") or result.endsWith(".safetensors"):
    let lastDot = result.rfind('.')
    let binCandidate = result[0 ..< lastDot] & ".bin"
    if fileExists(binCandidate):
      return binCandidate
