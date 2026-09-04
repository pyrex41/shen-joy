# PRD milestone evidence

This file distinguishes reproducible local evidence from unavailable physical
hardware evidence. `nix flake check` is the release-gate command.

| Milestone | Locally verified evidence | Remaining external evidence |
|---|---|---|
| M0 | Allocation-free Odin VM, explicit statuses, unit demo | None |
| M1 | v1 sections/checksum/metadata, deterministic encoder, allocation-free validator, corrupt and truncation tests, CLI inspect/validate/run | None |
| M2 | Documented normalized input, hybrid locals/stack lowering, calls and proper tail recursion, resource report, Shen/CL 3.0.3 + kernel 41.2 differential flake check | Broader generated-program corpus is future coverage, not an advertised feature |
| M3 | Arena lists/vectors, static imports, mock ADC/GPIO controller, deterministic capacity failures | Copying and region heaps are unsupported profiles |
| M4 | Freestanding C99 runtime and reproducible `armv6m-none-eabi` RP2040 object | Physical boot, GPIO/ADC, board trace, RAM/flash/timing measurements |
| M5 | Synthesizable SystemVerilog arithmetic/boolean/branch subset and common Odin/C/RTL simulation vector | Board run and post-route device utilization/frequency |
| M6 | Static repeated-value scheduling and checked `dup-mul` superinstruction; portable instruction counts and AOT decision in `optimization.md` | Native AOT is deferred until representative board measurements justify its maintenance cost |

Unsupported language/device constructs are compilation errors. The RTL target
is a declared subset and must not receive heap, call/local, quotation, or
device-import images. There are no physical-hardware or speed claims in this
repository.
