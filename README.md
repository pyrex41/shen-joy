# shen-joy

`shen-joy` is an experiment in compiling a useful, explicitly bounded subset
of Shen into a small concatenative machine suitable for microcontrollers and
eventually FPGAs.

The complete product scope, requirements, milestones, and release gates are in
the [Product Requirements Document](PRD.md).

It is not another complete Shen runtime and it is not an ANS Forth.  Parsing,
typechecking, lambda lifting, closure analysis, and image construction happen
on a development machine.  A target receives a validated static image and a
small deterministic VM:

```text
Shen / KLambda
      |
      v
host lowering and validation
      |
      v
32-bit Joy-shaped image
      |
      +---- Odin reference/device VM
      +---- native AOT backend (later)
      +---- FPGA RTL engine (later)
```

The first VM has 32-bit instructions and values, caller-supplied data and
return stacks, no allocation, no garbage collector, and no operating-system
dependency.  It supports fixnums, booleans, direct calls/tail calls, branches,
and static Joy quotations through `quote` and `i`.

Build and test with the pinned toolchain:

```sh
nix flake check
nix run . -- --demo
```

The demo evaluates Joy-style `6 dup * 1 +` and prints `37`.

The subset is defined against the community ShenOSKernel 42.2, the kernel
shipped by shen-scheme 0.50. `nix flake check` differentially tests against a
pinned shen-scheme 0.50 build (`.#shen-reference`). See
[PROVENANCE.md](PROVENANCE.md) for the lineage and hashes, and
[docs/shen-to-joy.md](docs/shen-to-joy.md#kernel-baseline-shenoskernel-422)
for which kernel changes are in scope.

See [docs/shen-to-joy.md](docs/shen-to-joy.md) for why the compiler uses a
hybrid stack/local representation instead of mechanically translating all
lambda terms through S/K combinators.

The packaged CLI supports:

```sh
nix run . -- compile --profile core tests/differential.sjk --output program.sji
nix run . -- inspect program.sji
nix run . -- validate program.sji
nix run . -- run program.sji --fuel 100000
nix run . -- bench program.sji --iterations 500 --warmup 20
```

Profiles are `core` (no heap/imports), `arena` (bounded lists/vectors), and
`embedded` (arena plus declared device imports). The target never contains a
Shen reader, mutable dictionary, JIT, or host filesystem dependency.

For the reproducible comparison with shen-go, Bifrost composes both pinned port
toolchains and runs their steady-state VM benchmarks:

```sh
cd ../bifrost
nix run .#env -- shen-go shen-joy -- go run . bench shen-joy-vs-shen-go
```

The latest local measurement and exact method are recorded in
[docs/benchmark.md](docs/benchmark.md). Yggdrasil also exposes a bounded `joy`
target; unsupported KLambda is an explicit capability skip, not silently
interpreted on the device.
