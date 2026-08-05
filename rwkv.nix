{ lib, stdenv, cmake, ninja, patchelf
, cudaPackages, clblast, ocl-icd, vulkan-loader
, enableCuda ? true, enableVulkan ? false, enableCLBlast ? false
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "rwkv";
  version = "local";

  src = ./.;

  nativeBuildInputs = [ cmake ninja patchelf ];
  buildInputs = [
    vulkan-loader
  ] ++ lib.optionals enableCuda [
    cudaPackages.cudart
    cudaPackages.libcublas
    cudaPackages.libcublasLt
  ] ++ lib.optionals enableCLBlast [
    clblast
    ocl-icd
  ] ++ lib.optionals enableVulkan [
    vulkan-loader
  ];

  cmakeFlags = lib.optionals enableCuda [
    "-DRWKV_CUBLAS=ON"
    "-DCMAKE_CUDA_ARCHITECTURES=86"
  ] ++ lib.optionals enableCLBlast [
    "-DRWKV_CLBLAST=ON"
  ] ++ lib.optionals enableVulkan [
    "-DRWKV_VULKAN=ON"
  ];

  # Build only the shared library (no tests, no extras)
  cmakeFlags += [ "-DRWKV_STANDALONE=ON" ];

  postInstall = ''
    mkdir -p $out/lib
    mv *.so* $out/lib/
  '';

  # Let nixpkgs' autoAddDriverRunpath and removeStubsFromRunpath hooks run
  # by ensuring strictDeps and proper setup hooks are active.
  # The hooks are automatically sourced when building with cudaPackages.
  NIX_LDFLAGS = lib.optionalString enableCuda ''
    -Wl,-rpath,/run/opengl-driver/lib
  '';

  meta = with lib; {
    description = "RWKV language model inference library";
    license = licenses.mit;
    platforms = platforms.linux;
  };
})
