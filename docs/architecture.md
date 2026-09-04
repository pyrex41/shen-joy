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

The first implementation deliberately has no heap.  Bounded cons/vector
storage and a selectable collection policy are the next semantic layer.  A
no-collection arena profile is appropriate when image analysis can prove an
allocation ceiling; a compact copying collector is appropriate for longer
running devices.

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
