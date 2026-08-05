{ pkgs, ... }:

{
  # Development tools and dependencies
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

    # GPU Driver & Toolkit Dependencies
    vulkan-loader
    vulkan-headers
    vulkan-tools
    shaderc        # provides glslc (ggml-vulkan shader compile)
    glslang        # glslangValidator as fallback
    clblast
    ocl-icd

    # NVIDIA CUDA Toolkit (for rwkv.cpp GPU acceleration)
    cudaPackages.cuda_nvcc
    cudaPackages.cuda_cudart
    cudaPackages.libcublas
    cudaPackages.cuda_cupti
  ];

  languages.nim.enable = true;

  # LD_LIBRARY_PATH: nix pcre2 FIRST (grep needs 10.47 with version symbols),
  # then system libs (CUDA driver needs /usr/lib/x86_64-linux-gnu), then rwkv.cpp.
  env.LD_LIBRARY_PATH = "/nix/store/gvn2w8kxsxdjh1nsw88gp9fjyrcxwmkj-pcre2-10.47/lib:/run/opengl-driver/lib:${pkgs.lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    pkgs.gcc.cc.lib
    pkgs.vulkan-loader
    pkgs.clblast
    pkgs.ocl-icd
  ]}:$DEVENV_ROOT/rwkv.cpp:$DEVENV_ROOT/rwkv.cpp/ggml/src:.";

  # GPU-enabled build scripts
  scripts.build-cuda.exec = ''
    echo "Building rwkv.cpp with NVIDIA CUDA GPU acceleration..."
    cd $DEVENV_ROOT/rwkv.cpp
    rm -rf CMakeCache.txt CMakeFiles
    cmake . -DRWKV_CUBLAS=ON -DCMAKE_CUDA_ARCHITECTURES="86;80;75;89" -DCMAKE_BUILD_TYPE=Release
    make -j$(nproc)
    echo "rwkv.cpp (CUDA GPU sm_86) built successfully!"
  '';

  scripts.build-vulkan.exec = ''
    echo "Building rwkv.cpp with Vulkan GPU acceleration..."
    cd $DEVENV_ROOT/rwkv.cpp
    rm -rf CMakeCache.txt CMakeFiles
    cmake . -DRWKV_CLBLAST=ON -DCMAKE_BUILD_TYPE=Release
    make -j$(nproc)
    echo "rwkv.cpp (Vulkan/CLBlast GPU) built successfully!"
  '';

  scripts.build-hip.exec = ''
    echo "Building rwkv.cpp with AMD ROCm/HIP GPU acceleration..."
    cd $DEVENV_ROOT/rwkv.cpp
    rm -rf CMakeCache.txt CMakeFiles
    cmake . -DRWKV_HIPBLAS=ON -DCMAKE_BUILD_TYPE=Release
    make -j$(nproc)
    echo "rwkv.cpp (AMD ROCm/HIP GPU) built successfully!"
  '';

  scripts.convert-st-to-bin.exec = ''
    echo "Converting RWKV v7 safetensors model to GGML format..."
    python3 $DEVENV_ROOT/rwkv.cpp/python/convert_pytorch_to_ggml.py \
      $DEVENV_ROOT/models/rwkv7-g1h-2.9b-20260710-ctx10240-f16.st \
      $DEVENV_ROOT/models/rwkv7-g1h-2.9b-20260710-ctx10240-f16.bin FP16
  '';

  scripts.quantize-4bit.exec = ''
    echo "Quantizing RWKV v7 GGML model to 4-bit (Q4_0)..."
    python3 $DEVENV_ROOT/rwkv.cpp/python/quantize.py \
      $DEVENV_ROOT/models/rwkv7-g1h-2.9b-20260710-ctx10240-f16.bin \
      $DEVENV_ROOT/models/rwkv7-g1h-2.9b-20260710-ctx10240-q4_0.bin Q4_0
  '';

  scripts.build-all.exec = ''
    cd $DEVENV_ROOT
    nimble build
  '';

  scripts.run-generate.exec = ''
    cd $DEVENV_ROOT
    $DEVENV_ROOT/build/generate
  '';

  scripts.run-chat.exec = ''
    cd $DEVENV_ROOT
    $DEVENV_ROOT/build/chat
  '';
}
