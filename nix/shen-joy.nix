{ stdenv, odin }:
stdenv.mkDerivation {
  pname = "shen-joy";
  version = "0.1.0-dev";
  src = ../.;
  dontConfigure = true;
  nativeBuildInputs = [ odin ];
  buildPhase = ''
    odin test src
    bash ./scripts/build.sh
  '';
  installPhase = ''mkdir -p $out/bin; cp build/shen-joy $out/bin/shen-joy'';
}
