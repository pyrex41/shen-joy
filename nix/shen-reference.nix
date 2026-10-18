# Differential reference: Shen/CL v3.2.0 with the community ShenOSKernel
# 43.1 (Shen-Language/shen-sources tag shen-43.1). The source release carries
# precompiled kernel/compiler Lisp and is built with SBCL; the kernel archive
# is fetched separately so its bytes and VERSION remain release-gated.
{ stdenv, fetchurl, sbcl, gnumake, gnutar, gzip }:
let
  shenVersion = "3.2.0";
  kernelVersion = "43.1";
  src = fetchurl {
    url = "https://github.com/Shen-Language/shen-cl/releases/download/v${shenVersion}/shen-cl-v${shenVersion}-sources.tar.gz";
    sha256 = "444f562a7779ba7038b9dc39fe88108d6d75cc2e111036a8f27d3dc253b3d43e";
  };
  kernel = fetchurl {
    # Shen-Language/shen-sources tag shen-43.1, commit 715824a52b55e9c81a9501df8548ff3edd8411f5.
    url = "https://github.com/Shen-Language/shen-sources/releases/download/shen-${kernelVersion}/ShenOSKernel-${kernelVersion}.tar.gz";
    sha256 = "900eedef44f440af78f9395ed06e689ce1604546fc309f5bc7c8bc84cc651920";
  };
in
stdenv.mkDerivation {
  pname = "shen-reference";
  version = "shen-cl-${shenVersion}-kernel-${kernelVersion}";
  inherit src;
  nativeBuildInputs = [ sbcl gnumake gnutar gzip ];
  dontConfigure = true;
  dontStrip = true;
  postPatch = ''
    mkdir -p _kernel
    tar -xzf ${kernel} -C _kernel
    test -d _kernel/ShenOSKernel-${kernelVersion}
    test "$(cat _kernel/ShenOSKernel-${kernelVersion}/VERSION | tr -d '[:space:]')" = "${kernelVersion}"
  '';
  buildPhase = ''
    make build-sbcl
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp bin/sbcl/shen $out/bin/shen-reference
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    got="$($out/bin/shen-reference eval -e '(version)' | tr -d '[:space:]"')"
    echo "shen-reference (version) = $got"
    test "$got" = "${kernelVersion}"
  '';
}
