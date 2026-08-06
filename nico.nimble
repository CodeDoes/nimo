## Package info
version       = "0.1.0"
author        = "Developer"
description   = "Nim wrapper for rwkv.cpp (RWKV language model inference in C/C++)"
license       = "MIT"
srcDir        = "src"
binDir        = "build"
bin           = @["main", "generate", "chat", "test_rwkv_full", "bake_state", "nimwave_app", "harness", "quantize", "nimo", "jules"]

# Dependencies
requires "nim >= 2.0.0"
requires "illwave"
requires "nimwave"

# --- Global Compiler Switches ---
switch("passL", "-Lrwkv.cpp -Lrwkv.cpp/ggml/src")
switch("passL", "-Wl,-rpath=rwkv.cpp -Wl,-rpath=rwkv.cpp/ggml/src")

# --- Tasks ---

task build_libs, "Build GPU backend libraries (cuda, vulkan)":
  if not fileExists("rwkv.cpp/librwkv_cuda.so"):
    echo "Building CUDA backend library..."
    exec "cd rwkv.cpp && rm -rf CMakeCache.txt CMakeFiles"
    exec "cd rwkv.cpp && cmake . -DRWKV_CUBLAS=ON -DCMAKE_CUDA_ARCHITECTURES='86' -DCMAKE_BUILD_TYPE=Release"
    exec "cd rwkv.cpp && make -j$(nproc)"
    exec "cp rwkv.cpp/librwkv.so rwkv.cpp/librwkv_cuda.so"
    exec "patchelf --remove-rpath rwkv.cpp/librwkv_cuda.so 2>/dev/null || true"
    exec "patchelf --add-rpath '/usr/lib/x86_64-linux-gnu:/nix/store/vcv2v0ax22qnq4y1kz1wl944a73l83ii-cuda12.9-cuda_cudart-12.9.79/lib:/nix/store/ivk162xanmk3h55aiiicw2pccqfwv0bp-cuda12.9-libcublas-12.9.1.4-lib/lib' rwkv.cpp/librwkv_cuda.so"
    echo "CUDA library built: librwkv_cuda.so"
  echo "All GPU backend libraries built successfully!"

task build_all, "Build all Nim executables into build/":
  if not fileExists("rwkv.cpp/librwkv_cuda.so"):
    build_libsTask()
  mkdir "build"
  exec "nim c -o:build/main src/main.nim"
  exec "nim c -o:build/generate src/generate.nim"
  exec "nim c -o:build/chat src/chat.nim"
  exec "nim c -o:build/bake_state src/bake_state.nim"
  exec "nim c -o:build/test_rwkv_full src/test_rwkv_full.nim"
  exec "nim c -o:build/nimwave_app src/nimwave_app.nim"
  exec "nim c -o:build/harness src/harness.nim"
  exec "nim c -o:build/quantize src/quantize.nim"
  exec "nim c -o:build/nimo src/nimo.nim"

task unit, "Run the unit test suite (offline, no model needed)":
  mkdir "build"
  exec "nim c -d:harnessOffline --path:src -o:build/unit src/unit.nim"
  exec "build/unit"

task eval, "Alias for the unit test suite":
  unitTask()

task harness, "Run the harness (interactive agent)":
  if not fileExists("rwkv.cpp/librwkv_cuda.so"):
    build_libsTask()
  mkdir "build"
  exec "nim c --path:src -o:build/harness src/harness.nim"
  exec "./build/harness"

task generate, "Run generate command":
  if not fileExists("rwkv.cpp/librwkv_cuda.so"):
    build_libsTask()
  mkdir "build"
  exec "nim c --path:src -o:build/generate src/generate.nim"
  exec "./build/generate"

task chat, "Run interactive chat":
  if not fileExists("rwkv.cpp/librwkv_cuda.so"):
    build_libsTask()
  mkdir "build"
  exec "nim c --path:src -o:build/chat src/chat.nim"
  exec "./build/chat"

task nimo, "Run nimo CLI":
  if not fileExists("rwkv.cpp/librwkv_cuda.so"):
    build_libsTask()
  mkdir "build"
  exec "nim c --path:src -o:build/nimo src/nimo.nim"
  exec "./build/nimo"

task run, "Compile and run a source file (auto-builds if needed)":
  ## Usage: nimble run <source_file> [args...]
  ## Example: nimble run harness, nimble run nimo -- harness
  if paramCount() < 1:
    echo "Usage: nimble run <source_file> [args...]"
    echo "Example: nimble run harness, nimble run nimo -- harness"
    quit(1)
  
  let srcFile = paramStr(1)
  let outPath = "build/" & srcFile.replace(".", "_").replace("/", "_")
  
  # Build libs if needed
  if not fileExists("rwkv.cpp/librwkv_cuda.so"):
    echo "Building backend libraries..."
    build_libsTask()
  
  mkdir "build"
  
  # Compile
  echo "Compiling " & srcFile & "..."
  let compileCmd = "nim c --path:src -o:" & outPath & " " & srcFile
  exec(compileCmd)
  
  # Run with args
  if paramCount() > 1:
    var args = ""
    for i in 2 .. paramCount():
      if i > 2: args.add(" ")
      args.add(paramStr(i))
    let runCmd = outPath & " " & args
    exec(runCmd)
  else:
    exec(outPath)
