{ pkgs, ... }:

{
  # Development tools and dependencies
  packages = with pkgs; [
    nim
    cmake
    gnumake
    gcc
    pkg-config
  ];

  languages.nim.enable = true;

  # Set up LD_LIBRARY_PATH so librwkv.so and C/C++ dependencies are found automatically
  env.LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    pkgs.gcc.cc.lib
  ]}:$PRJ_ROOT/rwkv.cpp:$PRJ_ROOT/rwkv.cpp/ggml/src:.";

  # Helper scripts
  scripts.build-rwkv.exec = ''
    echo "Building rwkv.cpp..."
    cd $PRJ_ROOT/rwkv.cpp
    cmake -B build
    cmake --build build -j$(nproc)
    cp build/librwkv.so . 2>/dev/null || true
    echo "rwkv.cpp built successfully!"
  '';

  scripts.test-nim.exec = ''
    cd $PRJ_ROOT
    nim c -r test_rwkv_full.nim
  '';
}
