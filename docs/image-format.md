# Image format version 1

Version 1 images are deterministic, little-endian byte sequences. All offsets
are from the start of the image. Integers, instructions, values, and metadata
fields are unsigned 32-bit words unless stated otherwise. The instruction and
value encodings described below are frozen for version 1.

## Header and section table

The 32-byte header contains: magic `SJY1`; version (`u16`, currently 1);
header size (`u16`, 32); total byte size; section count (7); feature mask;
FNV-1a checksum; endian marker `0x01020304`; and a reserved zero word. The
checksum covers every image byte with its own four-byte field treated as zero.

Seven 16-byte section entries immediately follow the header. Each is
`kind, offset, byte-size, element-count`. The entries occur exactly once and
in this order: code, constants, functions, entries, imports, resources, debug.
Sections start on four-byte boundaries, do not overlap, and lie within the
declared total size. Padding is zero when emitted by the reference encoder.

- Code and constants contain four-byte instructions and values.
- A function is seven words: stable name ID, code-word address, arity, input
  count, output count, maximum data-stack words, maximum return-stack words.
- An entry is two words: stable name ID and function index.
- An import is five words: primitive ID, stable name ID, inputs, outputs, flags.
  Flag bit 0 denotes deterministic behavior; other bits are reserved.
- Resources are five words: required data-stack words, required return-stack
  words, heap words, heap profile, and default fuel.
- Debug is an optional opaque byte section. Production images may omit it.

Stable name IDs are 32-bit FNV-1a hashes of UTF-8 names. Collisions within a
table are rejected by host tooling. The reserved header word is the external
authentication hook: version 1 requires zero and signing systems wrap the
whole image rather than changing executable semantics.

## Instructions and values

An instruction is one word. Bits 31–24 contain the opcode and bits 23–0 contain
an unsigned address/index or signed two's-complement immediate/relative
operand. Branch offsets are relative to the instruction following the branch.
Direct call and quotation operands are absolute code-word addresses. Every
word is an instruction boundary.

Values use their low two bits as tags:

| Low bits | Meaning |
|---|---|
| `01` | signed 30-bit fixnum |
| `10` | immediate singleton (`false` is 2, `true` is 6) |
| `11` | static quotation/code-word address |
| `00` | linear-heap word index; zero is the empty list |

Opcodes 0–16 are `halt`, `push`, `dup`, `drop`, `swap`, `add`, `sub`, `mul`,
`eq`, `lt`, `jump`, `jump-false`, `call`, `tail-call`, `return`, `quote`, and
`i`. Opcodes 17–32 are `enter`, `load-local`, `invoke`, `push-true`,
`push-false`, `nil`, `cons`, `head`, `tail`, `nil?`, `vector-new`,
`vector-get`, `vector-set`, `push-constant`, `store-local`, and `dup-mul`.
`enter` packs arity in bits 11–0 and extra local count in bits 23–12.

Feature bits are: bit 0 arena heap, bit 1 device imports, bit 2 debug metadata,
and bit 3 superinstructions. Unknown feature bits are rejected. Version 1
supports the no-heap and invocation-lifetime arena profiles; region, copying,
and hosted profiles are reserved for later versions.

## Validation contract

The loader checks the complete header before slicing sections; uses widened
arithmetic for every offset/size calculation; checks ordering, alignment,
record sizes, checksum, opcode range, branch/call/quotation targets, function
and entry references, stack-effect metadata, unique primitive IDs, and the
selected target's resources and imports. Unknown versions, heap profiles,
opcodes, or nonzero reserved fields are rejected. Validation returns an
explicit status and does not allocate or panic on malformed bytes.

Compatibility is exact-major-version compatibility: this loader accepts only
version 1 and the documented feature bits. Adding a section, opcode meaning,
tag meaning, or incompatible metadata rule requires version 2. Producers may
omit debug bytes and unused imports/opcode families without changing version.

Runtime status numbers are stable in v1: 0 Ok, 1 Bad_Image, 2 Stack_Limit,
3 Return_Limit, 4 Type_Error, 5 Arithmetic_Overflow, 6 Fuel_Exhausted,
7 Heap_Limit, 8 Missing_Import, 9 Unsupported, 10 Heap_Bounds, and
11 Device_Error. No status unwinds through the firmware boundary.
