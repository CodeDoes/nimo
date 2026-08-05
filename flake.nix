{
  description = "Nim wrapper and CLI for RWKV v7 inference in C/C++ (rwkv.cpp)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
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
          pcre2  # nix grep needs pcre2-10.47+, but nixpkgs has 10.46
          vulkan-loader
          clblast
          ocl-icd
          # NVIDIA CUDA Toolkit
          cudaPackages.cuda_nvcc
          cudaPackages.cuda_cudart
          cudaPackages.libcublas
          cudaPackages.cuda_cuobjdump
        ];

        shellHook = ''
          # Prepend nix pcre2-10.47 to fix grep version warning
          # nixpkgs only has pcre2-10.46 which lacks .gnu.version_d symbols
          export LD_LIBRARY_PATH="/nix/store/gvn2w8kxsxdjh1nsw88gp9fjyrcxwmkj-pcre2-10.47/lib:$LD_LIBRARY_PATH"
          export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:/run/opengl-driver/lib:$LD_LIBRARY_PATH:$PWD/rwkv.cpp:$PWD/rwkv.cpp/ggml/src"
          echo "Nimo Flake DevShell Loaded!"
        '';
      };
    };
}
