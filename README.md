# shen-joy

`shen-joy` is an experiment in compiling a useful, explicitly bounded subset
of Shen into a small concatenative machine suitable for microcontrollers and
eventually FPGAs.

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

See [docs/shen-to-joy.md](docs/shen-to-joy.md) for why the compiler uses a
hybrid stack/local representation instead of mechanically translating all
lambda terms through S/K combinators.
