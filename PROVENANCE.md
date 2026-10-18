# Kernel provenance and lineage

shen-joy does not vendor or execute a Shen kernel. The device VM runs a
bounded subset derived from Shen semantics. Host tools (Yggdrasil's `joy`
builder, or hand-written normalized input) lower KLambda to the `.sjk` form
documented in [docs/shen-to-joy.md](docs/shen-to-joy.md). The kernel matters
in two places:

1. **Semantic baseline.** The subset is defined relative to
   ShenOSKernel 43.1. It covers the semantics of the KLambda that kernel
   emits for first-order programs, restricted as documented in
   `docs/shen-to-joy.md`.
2. **Differential reference.** `nix flake check` compares shen-joy's results
   for `tests/differential*.sjk` against a pinned reference Shen that runs the
   matching `tests/differential*.shen` sources.

## Lineage decision

Tracking issue: pyrex41/shen-joy#1 (umbrella pyrex41/bifrost#26,
pyrex41/yggdrasil#32). shen-joy follows the decision made for every port:
**option (a), adopt the community ShenOSKernel 43.1 wholesale.** The Tarver
S42.0 lineage (`S42.zip`) is not used.

| Field | Value |
|---|---|
| Kernel repository | `Shen-Language/shen-sources` |
| Tag | `shen-43.1` |
| Commit | `715824a52b55e9c81a9501df8548ff3edd8411f5` |
| Release asset | `ShenOSKernel-43.1.tar.gz` |
| Asset SHA-256 | `900eedef44f440af78f9395ed06e689ce1604546fc309f5bc7c8bc84cc651920` |
| `(version)` | `"43.1"` |

## Differential reference

Before this change, `nix/shen-reference.nix` built shen-scheme 0.50 on kernel
42.2. It now builds **Shen/CL v3.2.0**, the release that ships ShenOSKernel
43.1:

| Archive | Source | SHA-256 |
|---|---|---|
| `shen-cl-v3.2.0-sources.tar.gz` | `Shen-Language/shen-cl` release `v3.2.0` (commit `4844072dde0208c3e4b99dcbfea58e4fdfd812a6`), release asset | `444f562a7779ba7038b9dc39fe88108d6d75cc2e111036a8f27d3dc253b3d43e` |
| `ShenOSKernel-43.1.tar.gz` | kernel release above; fetched only to cross-check `(version)` | `900eedef44f440af78f9395ed06e689ce1604546fc309f5bc7c8bc84cc651920` |

The Shen/CL source release already contains the 43.1 kernel compiled to Lisp
(`compiled/*.lsp`), so building it needs no bootstrap Shen. The derivation
fetches and verifies the unmodified kernel archive. Its install check requires
`(version)` to equal the kernel release's `VERSION` file (`43.1`).

Shen/CL was chosen because its v3.2.0 source release is the maintained port
baseline and includes precompiled kernel/compiler Lisp. Its public stream
primitive names are also the port-facing contract recorded in
`docs/shen-to-joy.md`.

The reference binary is installed as `shen-reference`. The flake check runs
`shen-reference eval -l tests/<name>.shen` and compares
the first `SJ_RESULT=` line with `shen-joy run`.

## Scope of kernel changes since 41.2

See [docs/shen-to-joy.md](docs/shen-to-joy.md#kernel-baseline-shenoskernel-431)
for which kernel changes are in scope and which are deliberately excluded.
In short, no change in 41.3 through 43.1 alters the semantics of the bounded
subset. shen-joy's differential results (`92` and `51`) did not change, and
they match the 43.1 reference.
