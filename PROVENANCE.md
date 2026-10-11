# Kernel provenance and lineage

shen-joy does not vendor or execute a Shen kernel. The device VM runs a
bounded subset derived from Shen semantics. Host tools (Yggdrasil's `joy`
builder, or hand-written normalized input) lower KLambda to the `.sjk` form
documented in [docs/shen-to-joy.md](docs/shen-to-joy.md). The kernel matters
in two places:

1. **Semantic baseline.** The subset is defined relative to
   ShenOSKernel 42.2. It covers the semantics of the KLambda that kernel
   emits for first-order programs, restricted as documented in
   `docs/shen-to-joy.md`.
2. **Differential reference.** `nix flake check` compares shen-joy's results
   for `tests/differential*.sjk` against a pinned reference Shen that runs the
   matching `tests/differential*.shen` sources.

## Lineage decision

Tracking issue: pyrex41/shen-joy#1 (umbrella pyrex41/bifrost#26,
pyrex41/yggdrasil#32). shen-joy follows the decision made for every port:
**option (a), adopt the community ShenOSKernel 42.2 wholesale.** The Tarver
S42.0 lineage (`S42.zip`) is not used.

| Field | Value |
|---|---|
| Kernel repository | `Shen-Language/shen-sources` |
| Tag | `shen-42.2` |
| Commit | `73507e069fe147aefb728d632c4ce40bc6a7b314` |
| Release asset | `ShenOSKernel-42.2.tar.gz` |
| Asset SHA-256 | `1d02273003654d34ec020ae67cb214ecec410dee3350419ff807d82b652678d8` |
| `(version)` | `"42.2"` |

## Differential reference

Before this change, `nix/shen-reference.nix` built Shen/CL 3.0.3 on kernel
41.2 (`shen-cl-v3.0.3-sources.tar.gz`). It now builds **upstream shen-scheme
v0.50**, the release that ships ShenOSKernel 42.2:

| Archive | Source | SHA-256 |
|---|---|---|
| `shen-scheme-v0.50-src.tar.gz` | `tizoc/shen-scheme` tag `v0.50` (commit `1bc774359eefe282823570545afe48ee50b0d544`), release asset | `2959ee95b4bd83e02a88f1220cc4857f66c5587a5928abc9f7e0d17136471986` |
| `csv10.3.0.tar.gz` | `cisco/ChezScheme` release v10.3.0 (the version and checksum pinned in shen-scheme 0.50's Makefile) | `d237d9874c6e8b0ccf7758daa8286a6e825528b13ce3b2bca56eb1f73cddbc2c` |
| `ShenOSKernel-42.2.tar.gz` | kernel release above; fetched only to cross-check `(version)` | `1d02273003654d34ec020ae67cb214ecec410dee3350419ff807d82b652678d8` |

The shen-scheme source release already contains the 42.2 kernel compiled to
Scheme (`compiled/*.scm`), so building it needs no bootstrap Shen. The
derivation pre-extracts the Chez archive so that the upstream Makefile does not
download anything inside the Nix sandbox. Its install check requires
`(version)` to equal the kernel release's `VERSION` file (`42.2`).

shen-scheme was chosen over the 42.2 branch of pyrex41/shen-cl because shen-cl
has no source release with a precompiled kernel. Building it requires an
existing Shen (`make precompile SHEN=...`), so a sandboxed Nix build would need
a bootstrap step. shen-scheme 0.50 also defines the "Shen 0.50 parity" target.

The reference binary is installed as both `shen-scheme` and `shen-reference`.
The flake check runs `shen-reference script tests/<name>.shen` and compares
the first `SJ_RESULT=` line with `shen-joy run`.

## Scope of kernel changes since 41.2

See [docs/shen-to-joy.md](docs/shen-to-joy.md#kernel-baseline-shenoskernel-422)
for which kernel changes are in scope and which are deliberately excluded.
In short, no change in 41.3 through 42.2 alters the semantics of the bounded
subset. shen-joy's differential results (`92` and `51`) did not change, and
they match the 42.2 reference.
