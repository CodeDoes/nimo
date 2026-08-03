#!/usr/bin/env bash
# Build rwkv.cpp with the AMD GPU backend (ggml-vulkan) into rwkv.cpp/build-amd,
# WITHOUT touching the existing CUDA librwkv.so (out-of-source cmake build).
#
# AMD on Linux is reached via Vulkan (RADV). Two things are required that are
# NOT currently set up on this machine:
#   1. glslang (or shaderc) to compile ggml's GLSL -> SPIR-V shaders at build time
#   2. a small patch to rwkv.cpp/CMakeLists.txt: it links ggml-metal/cuda/hip/rpc
#      but not ggml-vulkan, so we must add it to RWKV_EXTRA_LIBS + PIC props.
#
# Run:   devenv shell scripts/build/amd-vulkan.sh
set -eu
cd "$(dirname "$0")/../.."            # repo root
CM="$PWD/rwkv.cpp/CMakeLists.txt"

echo "== prerequisites =="
fail=0
command -v glslangValidator >/dev/null 2>&1 || command -v glslang >/dev/null 2>&1 || { echo "  MISSING glslang (add pkgs.glslang to devenv.nix)"; fail=1; }
command -v vulkaninfo >/dev/null 2>&1 || { echo "  MISSING vulkan-tools"; fail=1; }
grep -q 'ggml-vulkan' "$CM" || { echo "  rwkv.cpp must link ggml-vulkan (CMakeLists patch needed)"; fail=1; }
if [[ $fail -eq 1 ]]; then echo "cannot build AMD backend yet (see above)."; exit 1; fi

echo "== configure (build-amd, out-of-source) =="
cd rwkv.cpp
rm -rf build-amd && mkdir build-amd && cd build-amd
cmake .. -DRWKV_BUILD_SHARED_LIBRARY=ON -DGGML_VULKAN=ON -DGGML_CUDA=OFF \
         -DCMAKE_BUILD_TYPE=Release
echo "== build =="
make -j"$(nproc)"
echo "== done: rwkv.cpp/build-amd/librwkv.so =="
echo "Now run the AMD smoke test:"
echo "  NIMO_AMD_LIB=rwkv.cpp/build-amd/librwkv.so devenv shell scripts/smoke_test.sh"