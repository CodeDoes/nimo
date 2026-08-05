{ pkgs, ... }:

{
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
    vulkan-loader
    vulkan-headers
    shaderc
    glslang
    clblast
    ocl-icd
    cudaPackages.cuda_nvcc
    cudaPackages.cuda_cudart
    cudaPackages.libcublas
  ];

  languages.nim.enable = true;

  env.LD_LIBRARY_PATH = "/usr/lib/x86_64-linux-gnu:/run/opengl-driver/lib:${pkgs.lib.makeLibraryPath [
    pkgs.vulkan-loader
    pkgs.clblast
    pkgs.ocl-icd
  ]}:$DEVENV_ROOT/rwkv.cpp:$DEVENV_ROOT/rwkv.cpp/ggml/src:.";

  scripts.build-cuda.exec = ''
    cd $DEVENV_ROOT/rwkv.cpp
    rm -rf CMakeCache.txt CMakeFiles
    cmake . -DRWKV_CUBLAS=ON -DCMAKE_CUDA_ARCHITECTURES="86" -DCMAKE_BUILD_TYPE=Release
    make -j$(nproc)
  '';
}
