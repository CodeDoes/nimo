import std/[os, strformat]
import ./tokenizer

proc testTokenizer() =
  let vocabPath = "rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt"
  echo "Loading vocab from ", vocabPath, "..."
  let tok = loadWorldTokenizer(vocabPath)
  echo "Loaded tokens count: ", tok.indexToToken.len

  let testStrings = [
    "Hello World!",
    "The RWKV v7 language model is running in Nim!",
    "User: What is 2 + 2?\n\nBot: 2 + 2 = 4.",
    "你好世界！RWKV 7 模型 test 123 🎉"
  ]

  for s in testStrings:
    let encoded = tok.encode(s)
    let decoded = tok.decode(encoded)
    echo &"Original: \"{s}\""
    echo &"Encoded ({encoded.len} tokens): {encoded}"
    echo &"Decoded:  \"{decoded}\""
    doAssert decoded == s, &"Mismatch between original and decoded!\nOriginal: {s}\nDecoded:  {decoded}"
    echo "---"

  echo "Tokenizer test passed successfully!"

when isMainModule:
  testTokenizer()
