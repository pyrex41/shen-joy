# Differential reference: upstream shen-scheme v0.50, which ships the
# community ShenOSKernel 42.2 (Shen-Language/shen-sources tag shen-42.2).
# See PROVENANCE.md for the lineage decision and every pinned hash.
#
# The shen-scheme source release already contains the kernel precompiled to
# Scheme (`compiled/*.scm`), so no bootstrap Shen is needed. Its Makefile
# normally downloads Chez Scheme itself; here the Chez archive is fetched by
# Nix with the same SHA-256 the Makefile pins and is pre-extracted, so the
# build runs offline inside the sandbox.
{ stdenv, fetchurl, libuuid, gnutar, gzip }:
let
  shenSchemeVersion = "0.50";
  kernelVersion = "42.2";
  chezVersion = "10.3.0";
  src = fetchurl {
    # tizoc/shen-scheme tag v0.50, commit 1bc774359eefe282823570545afe48ee50b0d544
    url = "https://github.com/tizoc/shen-scheme/releases/download/v${shenSchemeVersion}/shen-scheme-v${shenSchemeVersion}-src.tar.gz";
    sha256 = "2959ee95b4bd83e02a88f1220cc4857f66c5587a5928abc9f7e0d17136471986";
  };
  chez = fetchurl {
    url = "https://github.com/cisco/ChezScheme/releases/download/v${chezVersion}/csv${chezVersion}.tar.gz";
    sha256 = "d237d9874c6e8b0ccf7758daa8286a6e825528b13ce3b2bca56eb1f73cddbc2c";
  };
  # Not compiled here (the source release carries the compiled kernel); it is
  # fetched so the build fails if the pinned release bytes ever change and so
  # the reported `(version)` can be checked against the release's VERSION file.
  kernel = fetchurl {
    # Shen-Language/shen-sources tag shen-42.2, commit 73507e069fe147aefb728d632c4ce40bc6a7b314
    url = "https://github.com/Shen-Language/shen-sources/releases/download/shen-${kernelVersion}/ShenOSKernel-${kernelVersion}.tar.gz";
    sha256 = "1d02273003654d34ec020ae67cb214ecec410dee3350419ff807d82b652678d8";
  };
in
stdenv.mkDerivation {
  pname = "shen-reference";
  version = "shen-scheme-${shenSchemeVersion}-kernel-${kernelVersion}";
  inherit src;
  buildInputs = [ libuuid ];
  nativeBuildInputs = [ gnutar gzip ];
  dontConfigure = true;
  dontStrip = true;
  enableParallelBuilding = false;
  postPatch = ''
    mkdir -p _build/chez
    tar -xzf ${chez} -C _build/chez
    test -d _build/chez/csv${chezVersion}
    patchShebangs _build/chez/csv${chezVersion}
    touch _build/chez/.csv${chezVersion}-d237d9874c6e8b0ccf7758daa8286a6e825528b13ce3b2bca56eb1f73cddbc2c.extracted
  '';
  buildPhase = ''
    runHook preBuild
    make prefix=$out
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    make install prefix=$out
    ln -s shen-scheme $out/bin/shen-reference
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    expected="$(tar -xzOf ${kernel} ShenOSKernel-${kernelVersion}/VERSION | tr -d '[:space:]')"
    test "$expected" = "${kernelVersion}"
    got="$($out/bin/shen-reference eval -e '(version)' | tr -d '[:space:]"')"
    echo "shen-reference (version) = $got"
    test "$got" = "$expected"
  '';
}
