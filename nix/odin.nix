{ stdenv, src, llvmPackages_22, coreutils, which, makeWrapper }:
llvmPackages_22.stdenv.mkDerivation {
  pname = "odin-pinned";
  version = "dev-2026-09";
  inherit src;
  strictDeps = true;
  nativeBuildInputs = [ llvmPackages_22.clang llvmPackages_22.llvm llvmPackages_22.lld coreutils which makeWrapper ];
  dontConfigure = true;
  buildPhase = ''export LLVM_CONFIG=${llvmPackages_22.llvm.dev}/bin/llvm-config; export CXX=${llvmPackages_22.clang}/bin/clang++; ./build_odin.sh release'';
  installPhase = ''mkdir -p $out/bin $out/share/odin; cp odin $out/bin/odin; cp -r base core shared vendor $out/share/odin/; wrapProgram $out/bin/odin --set ODIN_ROOT $out/share/odin'';
}
