# Kernel provenance and lineage

shen-joy does not vendor or execute a Shen kernel. The device VM runs a
bounded subset derived from Shen semantics. Host tools (Yggdrasil's `joy`
builder, or hand-written normalized input) lower KLambda to the `.sjk` form
documented in [docs/shen-to-joy.md](docs/shen-to-joy.md). The kernel matters
in two places:

1. **Semantic baseline.** The subset is defined relative to
   ShenOSKernel 43.2. It covers the semantics of the KLambda that kernel
   emits for first-order programs, restricted as documented in
   `docs/shen-to-joy.md`.
2. **Differential reference.** `nix flake check` compares shen-joy's results
   for `tests/differential*.sjk` against a pinned reference Shen that runs the
   matching `tests/differential*.shen` sources.

## Lineage decision

Tracking issue: pyrex41/shen-joy#1 (umbrella pyrex41/bifrost#26,
pyrex41/yggdrasil#32). shen-joy follows the decision made for every port:
**option (a), adopt the community ShenOSKernel 43.2 wholesale.** The Tarver
S42.0 lineage (`S42.zip`) is not used.

| Field | Value |
|---|---|
| Kernel repository | `Shen-Language/shen-sources` |
| Tag | `shen-43.2` (tag object `7b7563e5`) |
| Commit | `e6947f507ebc03f7ade5d2a8d971bd05d84a5bae` |
| Release asset | `ShenOSKernel-43.2.tar.gz` |
| Asset SHA-256 | `23c71508f0de24785e1f127ea4fab440081904d81c463090bc642ee840417f32` |
| `(version)` | `"43.2"` |

## Differential reference

The differential reference is **Shen/CL v3.2.1**, the first Shen/CL release
on ShenOSKernel 43.2. It is a release of the `pyrex41/shen-cl` fork; upstream
`Shen-Language/shen-cl` has no 43.2 release (its latest, v3.2.0, ships 43.1).

| Archive | Source | SHA-256 |
|---|---|---|
| `shen-cl-v3.2.1-sources.tar.gz` | `pyrex41/shen-cl` release `v3.2.1` (commit `120f387d7ac879a57f87ce65ad0c094c85a3f385`), release asset | `bf20620140b0c88e1e9763bd5a321e1844d18980b9d0c0ded5a080267b525470` |
| `ShenOSKernel-43.2.tar.gz` | kernel release above; fetched only to cross-check `(version)` | `23c71508f0de24785e1f127ea4fab440081904d81c463090bc642ee840417f32` |

The Shen/CL source release already contains the 43.2 kernel compiled to Lisp
(`compiled/*.lsp`, which sets `*version*` to `"43.2"` and defines
`shen.by-hypothesis-h`), so building it needs no bootstrap Shen. The
derivation fetches and verifies the unmodified kernel archive. Its install
check requires `(version)` to equal the kernel release's `VERSION` file
(`43.2`).

The 43.1 to 43.2 delta is the version string, an empty-list guard in
`shen.by-hypothesis` and `shen.search-user-datatypes` (new helpers
`shen.by-hypothesis-h` and `shen.search-user-datatypes-h`, both in the host
type checker), and gensym renumbering. None of it changes the KLambda
semantics of subset programs.

History: the reference was shen-scheme 0.50 on kernel 42.2, then upstream
Shen/CL v3.2.0 on 43.1 (`shen-cl-v3.2.0-sources.tar.gz`, SHA-256
`444f562a7779ba7038b9dc39fe88108d6d75cc2e111036a8f27d3dc253b3d43e`), and is now
Shen/CL v3.2.1 on 43.2.

Shen/CL was chosen because its source release is the maintained port
baseline and includes precompiled kernel/compiler Lisp. Its public stream
primitive names are also the port-facing contract recorded in
`docs/shen-to-joy.md`.

The reference binary is installed as `shen-reference`. The flake check runs
`shen-reference eval -l tests/<name>.shen` and compares
the first `SJ_RESULT=` line with `shen-joy run`.

## Scope of kernel changes since 41.2

See [docs/shen-to-joy.md](docs/shen-to-joy.md#kernel-baseline-shenoskernel-432)
for which kernel changes are in scope and which are deliberately excluded.
In short, no change in 41.3 through 43.2 alters the semantics of the bounded
subset. shen-joy's differential results (`92` and `51`) did not change, and
they match the 43.2 reference.
