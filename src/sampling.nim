## Sampling and Token Generation Utilities for RWKV

import std/[math, random, algorithm, strutils]

type
  Pair* = object
    prob*: float32
    idx*: int

proc softmax*(logits: openArray[float32]): seq[float32] =
  ## Computes numerically stable softmax probabilities over logits.
  result = newSeq[float32](logits.len)
  if logits.len == 0: return

  var maxVal = logits[0]
  for v in logits:
    if v > maxVal: maxVal = v

  var sumExp = 0.0f
  for i, v in logits:
    let e = exp(v - maxVal)
    result[i] = e
    sumExp += e

  if sumExp > 0.0f:
    for i in 0 ..< result.len:
      result[i] /= sumExp

proc sampleLogits*(logits: openArray[float32], temperature: float32 = 0.7f, topP: float32 = 0.7f, rng: var Rand): int =
  ## Samples next token index from logits using Temperature and Top-P (nucleus) sampling.
  if logits.len == 0: return 0

  if temperature <= 0.001f:
    var maxIdx = 0
    var maxVal = logits[0]
    for i, v in logits:
      if v > maxVal:
        maxVal = v
        maxIdx = i
    return maxIdx

  var probs = softmax(logits)

  if topP < 1.0f and topP > 0.0f:
    var pairs = newSeq[Pair](probs.len)
    for i in 0 ..< probs.len:
      pairs[i] = Pair(prob: probs[i], idx: i)

    pairs.sort(proc(a, b: Pair): int = cmp(b.prob, a.prob))

    var cumSum = 0.0f
    var cutoffIdx = pairs.len - 1
    for i, p in pairs:
      cumSum += p.prob
      if cumSum >= topP:
        cutoffIdx = i
        break

    var keptSum = 0.0f
    var keptProbs = newSeq[float32](probs.len)
    for i in 0 .. cutoffIdx:
      var p = pairs[i].prob
      if temperature != 1.0f:
        p = pow(p, 1.0f / temperature)
      keptProbs[pairs[i].idx] = p
      keptSum += p

    if keptSum > 0.0f:
      for i in 0 ..< probs.len:
        probs[i] = keptProbs[i] / keptSum

  elif temperature != 1.0f:
    var sumP = 0.0f
    for i in 0 ..< probs.len:
      probs[i] = pow(probs[i], 1.0f / temperature)
      sumP += probs[i]
    if sumP > 0.0f:
      for i in 0 ..< probs.len:
        probs[i] /= sumP

  let r = rng.rand(1.0f)
  var accum = 0.0f
  for i, p in probs:
    accum += p
    if r <= accum:
      return i

  return probs.len - 1

const StopSequences* = [
  "\n\nUser:",
  "\nUser:",
  "\n\nUser",
  "\nUser",
  "\n\nHuman:",
  "\nHuman:",
  "\n\nUs\ner:",
  "\nUs\ner:",
  "\nUser :",
  "\n\nUser :",
  "<|endoftext|>",
  "</s>"
]

proc endsWithStopSequence*(s: string): bool =
  ## Checks if string ends with any standard chat stop sequence.
  for stopSeq in StopSequences:
    if s.endsWith(stopSeq):
      return true
  return false

proc maxStopPrefixLen*(s: string): int =
  ## Returns length of longest suffix of `s` that matches a prefix of any stop sequence.
  result = 0
  for stopSeq in StopSequences:
    for prefixLen in 1 .. stopSeq.len:
      let prefix = stopSeq[0 ..< prefixLen]
      if s.endsWith(prefix):
        if prefixLen > result:
          result = prefixLen
