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

  scripts.nimo-harness.exec = ''
    cd $DEVENV_ROOT
    nimble run harness "$@"
  '';

  scripts.nimo-generate.exec = ''
    cd $DEVENV_ROOT
    nimble run generate -- "$@"
  '';

  scripts.nimo-doctor.exec = ''
    cd $DEVENV_ROOT
    nimble run nimo doctor "$@"
  '';

  scripts.nimo-unit.exec = ''
    cd $DEVENV_ROOT
    nimble unit "$@"
  '';

  scripts.nimo-test.exec = ''
    cd $DEVENV_ROOT
    # L0: in-process offline unit suite (fast, no model)
    nim c -d:harnessOffline -o:build/unit src/unit.nim
    build/unit
    # L1: black-box CLI integration with a scripted model (fast, no model)
    nim c -d:harnessOffline -o:build/harness_offline src/harness.nim
    bash scripts/cli_test.sh
    echo "=== nimo test: L0 + L1 done. Add L2 real-model smoke with: scripts/smoke_test.sh"
  '';

  scripts.nimo-new.exec = ''
    cd $DEVENV_ROOT
    nimble run nimo new "$@"
  '';

  scripts.nimo-chat.exec = ''
    cd $DEVENV_ROOT
    nimble run chat "$@"
  '';
}
