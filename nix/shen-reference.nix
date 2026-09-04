{ stdenv, src, sbcl, gnumake }:
stdenv.mkDerivation {
  pname = "shen-reference";
  version = "3.0.3-shen-41.2";
  inherit src;
  nativeBuildInputs = [ sbcl gnumake ];
  dontConfigure = true;
  dontStrip = true;
  buildPhase = ''
    make build-sbcl
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp bin/sbcl/shen $out/bin/shen-reference
  '';
}
