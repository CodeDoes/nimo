{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    nim
    cmake
    gnumake
    gcc
    pkg-config
    python3
    python3Packages.safetensors
    python3Packages.torch
    python3Packages.numpy
    vulkan-loader
    clblast
    ocl-icd
  ];

  shellHook = ''
    export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:/run/opengl-driver/lib:$LD_LIBRARY_PATH:$PWD/rwkv.cpp:$PWD/rwkv.cpp/ggml/src"
    echo "Nimo Development Shell Loaded!"
  '';
}
