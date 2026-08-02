## Global Configuration for RWKV Nim

const
  DefaultModelPath* = "models/rwkv7-g1h-2.9b-20260710-ctx10240-f16.bin"
  DefaultVocabPath* = "rwkv.cpp/python/rwkv_cpp/rwkv_vocab_v20230424.txt"
  DefaultPrompt* = "User: Hi!\n\nBot: Hello! How can I help you today?"
  DefaultGenLength* = 60
  DefaultTemp* = 0.7f
  DefaultTopP* = 0.7f
  DefaultChunkSize* = 16
  DefaultThreads* = 4
