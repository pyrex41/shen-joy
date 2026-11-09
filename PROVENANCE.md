# Kernel provenance and lineage

shen-joy does not vendor or execute a Shen kernel. The device VM runs a
bounded subset derived from Shen semantics. Host tools (Yggdrasil's `joy`
builder, or hand-written normalized input) lower KLambda to the `.sjk` form
documented in [docs/shen-to-joy.md](docs/shen-to-joy.md). The kernel matters
in two places:

1. **Semantic baseline.** The subset is defined relative to
   ShenOSKernel 43.4. It covers the semantics of the KLambda that kernel
   emits for first-order programs, restricted as documented in
   `docs/shen-to-joy.md`.
2. **Differential reference.** `nix flake check` compares shen-joy's results
   for `tests/differential*.sjk` against a pinned reference Shen that runs the
   matching `tests/differential*.shen` sources.

## Lineage decision

Tracking issue: pyrex41/shen-joy#1 (umbrella pyrex41/bifrost#26,
pyrex41/yggdrasil#32). shen-joy follows the decision made for every port:
**option (a), adopt the community ShenOSKernel 43.4 wholesale.** The Tarver
S42.0 lineage (`S42.zip`) is not used.

| Field | Value |
|---|---|
| Kernel repository | `Shen-Language/shen-sources` |
| Tag | `shen-43.4` (tag object `40fd3358`) |
| Commit | `f34b307b490880eedcfe1f5e5d3cc24ca3d2602e` |
| Release asset | `ShenOSKernel-43.4.tar.gz` |
| Asset SHA-256 | `15e7972e6bf0cd65d37c2eba85750b8839d2dbadda41027eae0c88e5017a2756` |
| `(version)` | `"43.4"` |

## Differential reference

The differential reference is **Shen/CL v3.3.0**, the Shen/CL release on
ShenOSKernel 43.4. It is a release of the `pyrex41/shen-cl` fork; upstream
`Shen-Language/shen-cl` has no 43.4 release (its latest, v3.2.0, ships 43.1).

| Archive | Source | SHA-256 |
|---|---|---|
| `shen-cl-v3.3.0-sources.tar.gz` | `pyrex41/shen-cl` release `v3.3.0` (commit `b4759cd82dd13e7f3ffaee402cee4c325c957dcd`), release asset | `4c901d693ec3cbf6b94f09372c34e0ede3075e56345001a8904c54a199011cf0` |
| `ShenOSKernel-43.4.tar.gz` | kernel release above; fetched only to cross-check `(version)` | `15e7972e6bf0cd65d37c2eba85750b8839d2dbadda41027eae0c88e5017a2756` |

The Shen/CL source release already contains the 43.4 kernel compiled to Lisp
(`compiled/*.lsp`, which sets `*version*` to `"43.4"` and defines
`shen.declare-with-signature`), so building it needs no bootstrap Shen. The
derivation fetches and verifies the unmodified kernel archive. Its install
check requires `(version)` to equal the kernel release's `VERSION` file
(`43.4`).

The 43.2 to 43.4 delta is the version string; the standard library's type
declarations and arity registrations pre-expanded through the `expand-dynamic`
extension (`shen.declare-with-signature`, `shen.update-lambda-table/precompiled`);
a factoriser fix that keeps the `condition failure` error for a `cond` with no
`true` clause; and gensym renumbering. None of it changes the KLambda
semantics of subset programs.

History: the reference was shen-scheme 0.50 on kernel 42.2, then upstream
Shen/CL v3.2.0 on 43.1 (`shen-cl-v3.2.0-sources.tar.gz`, SHA-256
`444f562a7779ba7038b9dc39fe88108d6d75cc2e111036a8f27d3dc253b3d43e`), then
Shen/CL v3.2.1 on 43.2 (`shen-cl-v3.2.1-sources.tar.gz`, SHA-256
`bf20620140b0c88e1e9763bd5a321e1844d18980b9d0c0ded5a080267b525470`), and is now
Shen/CL v3.3.0 on 43.4.

Shen/CL was chosen because its source release is the maintained port
baseline and includes precompiled kernel/compiler Lisp. Its public stream
primitive names are also the port-facing contract recorded in
`docs/shen-to-joy.md`.

The reference binary is installed as `shen-reference`. The flake check runs
`shen-reference eval -l tests/<name>.shen` and compares
the first `SJ_RESULT=` line with `shen-joy run`.

## Scope of kernel changes since 41.2

See [docs/shen-to-joy.md](docs/shen-to-joy.md#kernel-baseline-shenoskernel-434)
for which kernel changes are in scope and which are deliberately excluded.
In short, no change in 41.3 through 43.4 alters the semantics of the bounded
subset. shen-joy's differential results (`92` and `51`) did not change, and
they match the 43.4 reference.
