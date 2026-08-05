{
  description = "Nim wrapper and CLI for RWKV v7 inference";

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
      # Hardcode pcre2-10.47 path (exists in store, not exposed as package)
      pcre2_1047 = "/nix/store/gvn2w8kxsxdjh1nsw88gp9fjyrcxwmkj-pcre2-10.47";
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nim cmake gnumake gcc pkg-config
          python3 python3Packages.safetensors python3Packages.torch python3Packages.numpy
          vulkan-loader clblast ocl-icd
          cudaPackages.cuda_nvcc cudaPackages.cuda_cudart cudaPackages.libcublas
        ];

        # Add pcre2-10.47 to closure so it's always available
        nativeBuildInputs = [ pkgs.makeWrapper ];
        wrapperInputs = [ pcre2_1047 ];

        shellHook = ''
          # Prepend pcre2-10.47 (has PCRE2_10.47 symbols grep needs)
          export LD_LIBRARY_PATH="${pcre2_1047}/lib:/usr/lib/x86_64-linux-gnu:/run/opengl-driver/lib:\$LD_LIBRARY_PATH:$PWD/rwkv.cpp:$PWD/rwkv.cpp/ggml/src"
          echo "Nimo DevShell Loaded!"
        '';
      };
    };
}
