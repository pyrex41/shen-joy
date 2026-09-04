# Image format draft

The current executable unit is a sequence of little-endian 32-bit
instructions.  Bits 31–24 contain the opcode.  Bits 23–0 contain either an
unsigned absolute address or a signed relative/immediate operand.

Values are also 32 bits:

| Low bits | Meaning |
|---|---|
| `01` | signed 30-bit fixnum |
| `10` | immediate singleton (`false` or `true`) |
| `11` | static quotation/code address |
| `00` | reserved for future linear-heap references |

This is not yet a released persistent format.  A versioned header, section
table, function metadata, resource bounds, checksum, and target feature mask
must be specified before images are treated as durable artifacts.
