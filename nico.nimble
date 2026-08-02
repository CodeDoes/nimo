# Package info
version       = "0.1.0"
author        = "Developer"
description   = "Nim wrapper for rwkv.cpp (RWKV language model inference in C/C++)"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"

# --- Global Compiler Switches ---
# Tells Nim where to look for libraries during compilation
switch("passL", "-Lrwkv.cpp -Lrwkv.cpp/ggml/src")

# Binds the runtime paths into the binaries using rpath
switch("passL", "-Wl,-rpath=rwkv.cpp -Wl,-rpath=rwkv.cpp/ggml/src")

# --- Tasks ---
task build_cpp, "Build rwkv.cpp shared library":
  let cc = getEnv("CC", "")
  let cxx = getEnv("CXX", "")
  var cmd = "cd rwkv.cpp && "
  if cc.len > 0 and cxx.len > 0:
    cmd.add "CC=" & cc & " CXX=" & cxx & " "
  cmd.add "cmake . && make -j"
  exec cmd

task test, "Run the test suite":
  if not fileExists("rwkv.cpp/librwkv.so"):
    build_cppTask()
  exec "nim c -r src/test_rwkv_full.nim"

task generate, "Run text generation demo":
  if not fileExists("rwkv.cpp/librwkv.so"):
    build_cppTask()
  exec "nim c -r src/generate.nim"

task chat, "Run interactive TUI chat demo":
  if not fileExists("rwkv.cpp/librwkv.so"):
    build_cppTask()
  exec "nim c -r src/chat.nim"
