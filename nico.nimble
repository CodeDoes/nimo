## Package info
version       = "0.1.0"
author        = "Developer"
description   = "Nim wrapper for rwkv.cpp (RWKV language model inference in C/C++)"
license       = "MIT"
srcDir        = "src"
binDir        = "build"
bin           = @["main", "generate", "chat", "test_rwkv_full", "bake_state", "nimwave_app", "harness", "quantize", "nimo", "jules"]
installDirs   = @"bin"  # installs bin/ shim for PATH access

# Dependencies
requires "nim >= 2.0.0"
requires "illwave"
requires "nimwave"

# --- Global Compiler Switches ---
switch("passL", "-Lrwkv.cpp -Lrwkv.cpp/ggml/src")
switch("passL", "-Wl,-rpath=rwkv.cpp -Wl,-rpath=rwkv.cpp/ggml/src")

# --- Tasks ---

task build_libs, "Build GPU backend libraries (cuda, vulkan)":
  ## Builds two separate shared libraries:
  ##   - rwkv.cpp/librwkv_cuda.so   (CUDA backend with cuBLAS)
  ##   - rwkv.cpp/librwkv_vulkan.so (Vulkan/CLBlast backend)
  
  # Build CUDA library
  echo "Building CUDA backend library..."
  exec "cd rwkv.cpp && rm -rf CMakeCache.txt CMakeFiles"
  exec "cd rwkv.cpp && cmake . -DRWKV_CUBLAS=ON -DCMAKE_CUDA_ARCHITECTURES='86' -DCMAKE_BUILD_TYPE=Release"
  exec "cd rwkv.cpp && make -j$(nproc)"
  exec "cp rwkv.cpp/librwkv.so rwkv.cpp/librwkv_cuda.so"
  # Fix RUNPATH to remove stubs and add system CUDA driver path
  exec "patchelf --remove-rpath rwkv.cpp/librwkv_cuda.so 2>/dev/null || true"
  exec "patchelf --add-rpath '/usr/lib/x86_64-linux-gnu:/nix/store/vcv2v0ax22qnq4y1kz1wl944a73l83ii-cuda12.9-cuda_cudart-12.9.79/lib:/nix/store/ivk162xanmk3h55aiiicw2pccqfwv0bp-cuda12.9-libcublas-12.9.1.4-lib/lib' rwkv.cpp/librwkv_cuda.so"
  echo "CUDA library built: librwkv_cuda.so"
  
  # Build Vulkan library
  echo "Building Vulkan backend library..."
  exec "cd rwkv.cpp && rm -rf CMakeCache.txt CMakeFiles"
  exec "cd rwkv.cpp && cmake . -DRWKV_CLBLAST=ON -DCMAKE_BUILD_TYPE=Release"
  exec "cd rwkv.cpp && make -j$(nproc)"
  exec "cp rwkv.cpp/librwkv.so rwkv.cpp/librwkv_vulkan.so"
  echo "Vulkan library built: librwkv_vulkan.so"
  
  echo "All GPU backend libraries built successfully!"

task build_cpp, "Build rwkv.cpp shared library (legacy: builds CUDA only)":
  let cc = getEnv("CC", "")
  let cxx = getEnv("CXX", "")
  var cmd = "cd rwkv.cpp && "
  if cc.len > 0 and cxx.len > 0:
    cmd.add "CC=" & cc & " CXX=" & cxx & " "
  cmd.add "cmake . -DRWKV_CUBLAS=ON -DCMAKE_CUDA_ARCHITECTURES='86' -DCMAKE_BUILD_TYPE=Release && make -j"
  exec cmd

task build_all, "Build all Nim executables into build/":
  if not fileExists("rwkv.cpp/librwkv_cuda.so"):
    echo "Building backend libraries first..."
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

task jules, "Build the Jules CLI (needs SSL + system openssl)":
  mkdir "build"
  exec "nim c -d:ssl --passL:\"-L/usr/lib/x86_64-linux-gnu\" -o:build/jules src/jules.nim"

task jules_check, "Validate the configured Jules API key (offline+build)":
  exec "nimble jules"
  exec "build/jules check"

task eval, "Alias for the unit test suite (legacy name)":
  unitTask()

task bake_state, "Bake model state from prompt":
  if not fileExists("rwkv.cpp/librwkv_cuda.so"):
    build_libsTask()
  mkdir "build"
  exec "nim c -r -o:build/bake_state src/bake_state.nim"

task test, "Run the test suite":
  if not fileExists("rwkv.cpp/librwkv_cuda.so"):
    build_libsTask()
  mkdir "build"
  exec "nim c -r -o:build/test_rwkv_full src/test_rwkv_full.nim"

task chat, "Run interactive TUI chat demo":
  if not fileExists("rwkv.cpp/librwkv_cuda.so"):
    build_libsTask()
  mkdir "build"
  exec "nim c -r -o:build/chat src/chat.nim"

task nimwave, "Run the NIMWAVE TUI dashboard":
  if not fileExists("rwkv.cpp/librwkv_cuda.so"):
    build_libsTask()
  mkdir "build"
  exec "nim c -r -o:build/nimwave_app src/nimwave_app.nim"
