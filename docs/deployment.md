# Deployment targets and evidence

## Microcontroller target

The first concrete MCU target is the RP2040's Arm Cortex-M0+ (`armv6m-none-eabi`).
`runtime/c/shen_joy_vm.[ch]` is a freestanding, allocation-free C99 runtime
using caller-owned code, stacks, constants, heap, and device callback state.
The flake cross-compiles it with pinned LLVM using `-ffreestanding -nostdlib`
and checks the same source as a hosted conformance oracle. Firmware should put
the validated image/code arrays in flash and instantiate `sj_machine` in RAM.
Interrupts and multicore scheduling remain outside the VM.
The `mcu-runtime` flake output includes `resource.txt` from pinned LLVM's
`llvm-size`; it measures the relocatable runtime object only and is not a
claim about final firmware flash or RAM use.
For the 2026-09-04 pinned Clang 22 `-Oz` build, that object contains 1,870
bytes of text and zero data/BSS bytes. Caller-provided stacks, heap, image, and
firmware glue are deliberately absent from that number.

No RP2040 board is attached to this development environment. Consequently the
PRD M4 claims for booting on physical silicon, exercising a physical device,
measured flash/RAM/timing, and board trace matching are **not complete and are
not claimed**. The reproducible cross-compiled object is MCU-suitable build
evidence, not physical-hardware evidence.

## FPGA target

`rtl/shen_joy_core.sv` is a synthesizable multi-cycle reference for the v1
no-heap arithmetic/boolean/branch subset. It uses a ROM, a bounded stack RAM,
PC/SP registers, and one architectural instruction per cycle. Calls, locals,
quotations, heap objects, and imports are explicitly rejected by this RTL
profile; the host must enforce that profile before deployment.

The checked-in core, branch, and overflow vectors are consumed by the Odin
semantics, hosted/freestanding C implementation, and RTL testbench. Simulation
is reproducible in the flake with Icarus Verilog. The conformance output records
6, 4, and 3 architectural steps respectively, with matching results/statuses.
Pinned Yosys 0.68 reports zero design-check problems and 191 generic cells
(61 AND, 1 NAND, 1 NOT, 64 enabled flip-flops, 1 flip-flop, 1 XNOR, 62 XOR)
for this fixed-ROM test configuration. This is a generic synthesis measurement,
not placed device utilization. No FPGA board is attached, so no board
demonstration, post-place-and-route maximum clock, BRAM utilization, or
physical timing result is claimed. Generic simulation agreement is not a
substitute for those measurements.
