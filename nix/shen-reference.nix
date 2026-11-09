# Differential reference: Shen/CL v3.3.0 (pyrex41/shen-cl fork release) with
# the community ShenOSKernel 43.4 (Shen-Language/shen-sources tag shen-43.4). The source release carries
# precompiled kernel/compiler Lisp and is built with SBCL; the kernel archive
# is fetched separately so its bytes and VERSION remain release-gated.
{ stdenv, fetchurl, sbcl, gnumake, gnutar, gzip }:
let
  shenVersion = "3.3.0";
  kernelVersion = "43.4";
  src = fetchurl {
    # pyrex41/shen-cl tag v3.3.0, commit b4759cd82dd13e7f3ffaee402cee4c325c957dcd.
    url = "https://github.com/pyrex41/shen-cl/releases/download/v${shenVersion}/shen-cl-v${shenVersion}-sources.tar.gz";
    sha256 = "4c901d693ec3cbf6b94f09372c34e0ede3075e56345001a8904c54a199011cf0";
  };
  kernel = fetchurl {
    # Shen-Language/shen-sources tag shen-43.4, commit f34b307b490880eedcfe1f5e5d3cc24ca3d2602e.
    url = "https://github.com/Shen-Language/shen-sources/releases/download/shen-${kernelVersion}/ShenOSKernel-${kernelVersion}.tar.gz";
    sha256 = "15e7972e6bf0cd65d37c2eba85750b8839d2dbadda41027eae0c88e5017a2756";
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
