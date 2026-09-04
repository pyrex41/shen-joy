# Optimization evidence and decisions

The compiler uses a static stack schedule. Identical variable operands in a
binary expression reuse the loaded value; multiplication selects the checked
`dup-mul` superinstruction. On the checked `square+1` workload this changes
`load-local, dup, mul, push, add` to `load-local, dup-mul, push, add`: four
body fetches instead of five. This is an architectural instruction-count
measurement, not a wall-clock speed claim. Both paths use the same overflow
status and the Shen differential result remains 37.

The cross-implementation vectors record these measured architectural counts:

| Vector | SHA-256 (SRI) | Result/status | Instructions |
|---|---|---|---:|
| core | `sha256-bZES2+aOojL5pdvezRI0UlNmhidJSTiH0chsL7sUW10=` | 37 / Ok | 6 |
| branch | `sha256-UHevPPD/vH4joysVZZ6X8gEssAu3oooBLNcA3xj/sCc=` | 42 / Ok | 4 |
| overflow | `sha256-Pd5CJo2E7QWcmgxnM1SA7ee0Za8kO/cZvolNLhMvcY4=` | 0 / Arithmetic_Overflow | 3 |

Native AOT lowering was evaluated against the present workload and deferred.
The representative embedded controller is dominated by device callbacks, and
there is no physical-target timing baseline demonstrating that duplicating the
interpreter semantics in an AOT backend is justified. The freestanding C VM
is the MCU deployment artifact. An AOT backend remains behind the same image
validation and conformance contract when measured workloads establish a gate.
No native or FPGA speedup is claimed.
