# PRD milestone evidence

This file distinguishes reproducible local evidence from unavailable physical
hardware evidence. `nix flake check` is the release-gate command.

| Milestone | Locally verified evidence | Remaining external evidence |
|---|---|---|
| M0 | Allocation-free Odin VM, explicit statuses, unit demo | None |
| M1 | v1 sections/checksum/metadata, deterministic encoder, allocation-free validator, corrupt and truncation tests, CLI inspect/validate/run | None |
| M2 | Documented normalized input, hybrid locals/stack lowering, calls and proper tail recursion, resource report, differential flake check against shen-scheme 0.50 on ShenOSKernel 42.2 (see PROVENANCE.md) | Broader generated-program corpus is future coverage, not an advertised feature |
| M3 | Arena lists/vectors, static imports, mock ADC/GPIO controller, deterministic capacity failures | Copying and region heaps are unsupported profiles |
| M4 | Freestanding C99 runtime and reproducible `armv6m-none-eabi` RP2040 object | Physical boot, GPIO/ADC, board trace, RAM/flash/timing measurements |
| M5 | Synthesizable SystemVerilog arithmetic/boolean/branch subset and common Odin/C/RTL simulation vector | Board run and post-route device utilization/frequency |
| M6 | Static repeated-value scheduling and checked `dup-mul` superinstruction; portable instruction counts and AOT decision in `optimization.md` | Native AOT is deferred until representative board measurements justify its maintenance cost |

Unsupported language/device constructs are compilation errors. The RTL target
is a declared subset and must not receive heap, call/local, quotation, or
device-import images. There are no physical-hardware or speed claims in this
repository.

## Kernel baseline

The subset and the differential reference follow the community
ShenOSKernel 42.2 (`Shen-Language/shen-sources` tag `shen-42.2`, commit
`73507e0`), adopted wholesale per pyrex41/shen-joy#1. The previous reference
was Shen/CL 3.0.3 on kernel 41.2. [PROVENANCE.md](../PROVENANCE.md) records
the pinned hashes. [shen-to-joy.md](shen-to-joy.md#kernel-baseline-shenoskernel-422)
records which 42.x kernel changes are in or out of scope; none changes subset
semantics. An end-to-end 42.2 Yggdrasil shake for the `joy` target waits on
pyrex41/yggdrasil#32, because Yggdrasil still vendors S42.0.

Yggdrasil's current `joy` builder was run with shen-cl `kernel-42.2` as the
stage-1 host. The shaker itself still embeds S42.0 (manifest
`kernel-version=42-s42.20260825`). `tests/joy-sum.shen` builds and runs
(`32004000`). `tests/fib.shen` is a capability SKIP (exit 3) by design: its
`(output "fib 20 = ~A~%" ...)` is outside the single-`~A` output form, and
`fib` makes non-tail recursive calls, which the bounded return-stack proof
rejects. The joy target therefore cannot run `fib.shen` on any kernel version.
