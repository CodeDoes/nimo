{ pkgs, ... }:

{
  # Development tools and dependencies using Nix
  packages = with pkgs; [
    nim
    cmake
    gnumake
    gcc
    pkg-config
    python3
    python3Packages.safetensors
    python3Packages.torch
    python3Packages.numpy
  ];

  languages.nim.enable = true;

  # Set up LD_LIBRARY_PATH so librwkv.so and C/C++ dependencies are found automatically
  env.LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    pkgs.gcc.cc.lib
  ]}:$PRJ_ROOT/rwkv.cpp:$PRJ_ROOT/rwkv.cpp/ggml/src:.";

  # Nix-powered executable scripts
  scripts.build-rwkv.exec = ''
    echo "Building rwkv.cpp C++ shared library..."
    cd $PRJ_ROOT/rwkv.cpp
    cmake -B build
    cmake --build build -j$(nproc)
    cp build/librwkv.so . 2>/dev/null || true
    echo "rwkv.cpp built successfully!"
  '';

  scripts.convert-st-to-bin.exec = ''
    echo "Converting RWKV v7 safetensors model to GGML format..."
    python3 $PRJ_ROOT/rwkv.cpp/python/convert_pytorch_to_ggml.py \
      $PRJ_ROOT/models/rwkv7-g1h-2.9b-20260710-ctx10240-f16.st \
      $PRJ_ROOT/models/rwkv7-g1h-2.9b-20260710-ctx10240-f16.bin FP16
  '';

  scripts.quantize-4bit.exec = ''
    echo "Quantizing RWKV v7 GGML model to 4-bit (Q4_0)..."
    python3 $PRJ_ROOT/rwkv.cpp/python/quantize.py \
      $PRJ_ROOT/models/rwkv7-g1h-2.9b-20260710-ctx10240-f16.bin \
      $PRJ_ROOT/models/rwkv7-g1h-2.9b-20260710-ctx10240-q4_0.bin Q4_0
  '';

  scripts.build-all.exec = ''
    cd $PRJ_ROOT
    nimble build
  '';

  scripts.run-generate.exec = ''
    cd $PRJ_ROOT
    ./build/generate
  '';

  scripts.run-chat.exec = ''
    cd $PRJ_ROOT
    ./build/chat
  '';
}
