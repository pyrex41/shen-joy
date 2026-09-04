# Architecture

The project separates the host compiler from the target machine.  The target
does not parse Shen or Joy and does not maintain a mutable source dictionary.

## Host side

1. Read typed Shen or KLambda.
2. Reject features outside the selected target profile.
3. Lambda-lift and closure-convert the remaining program.
4. Infer stack effects and lower stack-friendly regions to concatenative code.
5. Retain indexed locals where pure stack rearrangement would increase code or
   maximum stack depth excessively.
6. Calculate exact or conservative bounds for stacks and heap.
7. Emit and validate a versioned image.

The existing Shen-Forth compiler is a potential source of KLambda and a
differential oracle.  It is not part of the device runtime.

## Target side

The core VM has a program counter, data-stack pointer, return-stack pointer,
and immutable code image.  All storage is supplied by its caller.  Opcodes
return explicit status values for bad images, resource exhaustion, type
errors, and unsupported facilities.

Version 1 has no-heap and bounded invocation-arena profiles. Cons cells occupy
three words (kind, head, tail); vectors occupy one header word plus their fixed
element count. References are tagged word indices, never host pointers. The
compiler conservatively sums statically visible allocation sites, and the VM
returns `Heap_Limit` or `Heap_Bounds` instead of allocating or panicking.

Device calls use a numeric import ID and a callback receiving the machine and
opaque caller context. The image records each import's stack effect and
determinism class; target validation checks capabilities, capacities, and IDs
before execution.

The callback ABI is `Status callback(u32 primitive_id, ^Machine, rawptr ctx)`.
Inputs are already on the data stack and a successful callback must consume
and produce exactly the declared counts. It must validate any address/length,
must not unwind through the VM, and reports failure with a stable status.

## Hardware mapping

- code image: ROM or block RAM;
- data and return stacks: separate block RAMs;
- top stack cells: registers;
- opcode and operand: one 32-bit fetch;
- direct calls and quotations: code addresses, never host pointers;
- future heap references: tagged indices into linear RAM.

Odin is the reference implementation and a practical native runtime.  FPGA
targets will implement the documented machine in RTL rather than synthesize
Odin source.

The repository also carries a freestanding C99 runtime cross-compiled for the
RP2040 Cortex-M0+ and a synthesizable SystemVerilog no-heap subset. See
`deployment.md` for exact evidence and explicit hardware limitations.
