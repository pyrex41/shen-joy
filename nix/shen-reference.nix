# Differential reference: Shen/CL v3.2.1 (pyrex41/shen-cl fork release) with
# the community ShenOSKernel 43.2 (Shen-Language/shen-sources tag shen-43.2). The source release carries
# precompiled kernel/compiler Lisp and is built with SBCL; the kernel archive
# is fetched separately so its bytes and VERSION remain release-gated.
{ stdenv, fetchurl, sbcl, gnumake, gnutar, gzip }:
let
  shenVersion = "3.2.1";
  kernelVersion = "43.2";
  src = fetchurl {
    # pyrex41/shen-cl tag v3.2.1, commit 120f387d7ac879a57f87ce65ad0c094c85a3f385.
    url = "https://github.com/pyrex41/shen-cl/releases/download/v${shenVersion}/shen-cl-v${shenVersion}-sources.tar.gz";
    sha256 = "bf20620140b0c88e1e9763bd5a321e1844d18980b9d0c0ded5a080267b525470";
  };
  kernel = fetchurl {
    # Shen-Language/shen-sources tag shen-43.2, commit e6947f507ebc03f7ade5d2a8d971bd05d84a5bae.
    url = "https://github.com/Shen-Language/shen-sources/releases/download/shen-${kernelVersion}/ShenOSKernel-${kernelVersion}.tar.gz";
    sha256 = "23c71508f0de24785e1f127ea4fab440081904d81c463090bc642ee840417f32";
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
