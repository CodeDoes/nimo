## Package info
version       = "0.1.0"
author        = "Developer"
description   = "Nim wrapper for rwkv.cpp (RWKV language model inference in C/C++)"
license       = "MIT"
srcDir        = "src"
binDir        = "build"
bin           = @["main", "generate", "chat", "test_rwkv_full", "bake_state", "nimwave_app", "harness_main"]

# Dependencies
requires "nim >= 2.0.0"
requires "illwave"
requires "nimwave"

# --- Global Compiler Switches ---
switch("passL", "-Lrwkv.cpp -Lrwkv.cpp/ggml/src")
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

task build_all, "Build all Nim executables into build/":
  if not fileExists("rwkv.cpp/librwkv.so"):
    build_cppTask()
  mkdir "build"
  exec "nim c -o:build/main src/main.nim"
  exec "nim c -o:build/generate src/generate.nim"
  exec "nim c -o:build/chat src/chat.nim"
  exec "nim c -o:build/bake_state src/bake_state.nim"
  exec "nim c -o:build/test_rwkv_full src/test_rwkv_full.nim"
  exec "nim c -o:build/nimwave_app src/nimwave_app.nim"

task eval, "Run harness evals (offline, no model needed)":
  mkdir "build"
  exec "nim c -d:harnessOffline -o:build/evals src/evals.nim"
  exec "build/evals"

task bake_state, "Bake model state from prompt":
  if not fileExists("rwkv.cpp/librwkv.so"):
    build_cppTask()
  mkdir "build"
  exec "nim c -r -o:build/bake_state src/bake_state.nim"

task test, "Run the test suite":
  if not fileExists("rwkv.cpp/librwkv.so"):
    build_cppTask()
  mkdir "build"
  exec "nim c -r -o:build/test_rwkv_full src/test_rwkv_full.nim"

task generate, "Run text generation demo":
  if not fileExists("rwkv.cpp/librwkv.so"):
    build_cppTask()
  mkdir "build"
  exec "nim c -r -o:build/generate src/generate.nim"

task chat, "Run interactive TUI chat demo":
  if not fileExists("rwkv.cpp/librwkv.so"):
    build_cppTask()
  mkdir "build"
  exec "nim c -r -o:build/chat src/chat.nim"

task nimwave, "Run the NIMWAVE TUI dashboard":
  if not fileExists("rwkv.cpp/librwkv.so"):
    build_cppTask()
  mkdir "build"
  exec "nim c -r -o:build/nimwave_app src/nimwave_app.nim"
