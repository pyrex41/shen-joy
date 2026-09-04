# shen-joy Product Requirements Document

**Status:** Initial product contract  
**Revision:** 2026-09-04  
**Project:** `shen-joy`  
**Primary implementation language:** Odin  
**Primary purpose:** Run statically compiled Shen-derived programs on bounded
microcontrollers and FPGA soft/hard machines.

## 1. Product summary

`shen-joy` is a host compiler, portable image format, and small deterministic
abstract machine for deploying a useful subset of Shen to constrained targets.

The development machine performs parsing, typechecking, specialization,
lambda lifting, closure analysis, stack-effect inference, resource analysis,
and image validation. The target does not need a Shen reader, evaluator,
typechecker, source dictionary, or interactive compiler. It receives a
validated static image and executes it using bounded, caller-provided memory.

The compiler uses Joy-like concatenative operations and static quotations
where they simplify data flow. The execution machine retains Forth-like direct
calls, tail calls, explicit stacks, and simple memory semantics. Indexed locals
remain available where a purely concatenative translation would increase code
size, execution count, or maximum stack depth.

The product is therefore neither a complete Joy nor an ANS Forth. It is a
Shen-oriented, Joy-shaped compiler target with a small Forth-shaped machine.

## 2. Problem

Existing Shen implementations assume a comparatively rich host environment:
dynamic allocation, symbols, closures, exceptions, streams, a reader, and in
many cases a general-purpose garbage collector. Those assumptions are poorly
matched to small microcontrollers and directly implementing them in FPGA logic
would consume unnecessary memory and complexity.

At the other extreme, manually rewriting each Shen application in C, Forth, or
HDL loses Shen's type system, metaprogramming environment, theorem-proving
tools, and high-level domain modelling.

The product must preserve Shen as a development language while removing
features that a particular deployed program does not require.

## 3. Product vision

A developer should be able to define and verify logic in Shen, choose an
embedded target profile, and produce a small deterministic image whose memory,
stack, instruction, and device requirements are known before deployment.

The same image semantics must be executable by:

- the Odin reference VM on a workstation;
- a hosted/device Odin runtime where the target is supported;
- a small MCU implementation in another systems language if needed;
- an FPGA RTL implementation of the documented machine;
- future native AOT backends.

## 4. Goals

### 4.1 Primary goals

1. Compile a useful, documented subset of Shen/KLambda into a compact static
   image.
2. Execute that image without an operating system, tracing GC, JIT, source
   parser, or mutable dictionary.
3. Bound or reject data stack, return stack, continuation stack, and heap usage
   before deployment whenever analysis can do so.
4. Use explicit runtime statuses rather than language panics or foreign
   exception unwinding.
5. Keep the core instruction and value formats straightforward to implement in
   FPGA RTL and on 32-bit MCUs.
6. Differentially verify compiled programs against a reference Shen runtime.
7. Permit target-specific device primitives through a declared, statically
   checked capability interface.

### 4.2 Secondary goals

- Support native AOT compilation of verified images when interpretation is too
  slow.
- Allow a larger hosted profile with more dynamic Shen features.
- Reuse selected compiler/JIT infrastructure from `odinforth` without making
  it part of the target runtime.
- Allow optional debugging metadata to be stripped from production images.

## 5. Non-goals

The initial product is not intended to provide:

- a complete Shen implementation on the device;
- an interactive Shen or Forth REPL on production targets;
- ANS Forth compatibility;
- full Joy semantics or runtime construction of arbitrary quotations;
- runtime parsing, compilation, `eval`, or source redefinition;
- transparent access to all host libraries;
- an optimizing JIT on microcontrollers;
- synthesis of Odin source directly into FPGA logic;
- unbounded allocation, recursion, or stack growth;
- hard real-time guarantees before worst-case timing analysis exists;
- silent fallback when a selected target cannot implement a feature.

## 6. Users and use cases

### 6.1 Embedded Shen developer

Uses Shen's type system and high-level abstractions to implement control logic,
protocol state machines, rule systems, parsers, symbolic transformations, and
small decision engines. Produces a target image and resource report.

### 6.2 Firmware integrator

Embeds the VM and image in existing firmware, supplies fixed memory regions and
device primitive callbacks, and handles explicit VM statuses.

### 6.3 FPGA implementer

Implements the versioned instruction set and value representation in RTL,
loads generated images into ROM/BRAM, and compares execution traces against the
Odin reference VM.

### 6.4 Language/runtime researcher

Experiments with Shen-to-concatenative lowering, stack scheduling,
specialization, closure elimination, heap policies, and hardware execution.

## 7. Product boundary

```text
Development host                         Deployment target
----------------                         -----------------
Shen source
    |
    v
Shen/KLambda reference frontend
    |
    v
profile checking
lambda lifting / specialization
hybrid local + Joy lowering
resource analysis
image validation
    |
    +---------- versioned image ------> loader/validator
                                               |
                                               v
                                      bounded abstract machine
                                               |
                                               v
                                      declared device primitives
```

The host compiler and target VM are independently testable. No target runtime
function may depend on the Shen reader or host compiler.

## 8. Language profile

### 8.1 Initial required subset

- signed fixnum constants;
- boolean constants;
- statically resolved functions with known arities;
- local variables introduced by compilation;
- sequencing;
- conditionals;
- equality and ordered fixnum comparisons;
- checked fixnum arithmetic;
- direct calls, tail calls, and bounded recursion;
- immutable static quotations and invocation through `i`;
- statically declared device primitives.

### 8.2 Planned data subset

- cons cells and empty list;
- bounded vectors;
- interned/static symbol IDs;
- immutable byte strings or target-selected string sections;
- restricted closure environments where specialization cannot eliminate them;
- explicit traps and error values;
- optional fixed-point numeric profiles.

### 8.3 Explicitly unsupported initially

- runtime `eval`;
- dynamic global rebinding;
- runtime symbol interning;
- arbitrary precision integers;
- general floating point unless selected by the target profile;
- arbitrary host streams and filesystem operations;
- mutation outside declared vectors, heap cells, and device primitives;
- runtime creation or inspection of arbitrary Joy quotations;
- source-level macros on the device.

Unsupported features must produce a host-side compilation diagnostic naming
the source construct and target capability. They must not become latent device
failures.

## 9. Joy and Forth design requirements

Joy is a compiler model, not a requirement to implement the complete language.
Static quotations are code addresses rather than heap-allocated lists. Useful
combinators may be introduced as verified IR operations or expanded by the host
compiler.

The compiler should produce concatenative sequences when they reduce runtime
state. For example:

```shen
(defun square+1 (X) (+ (* X X) 1))
```

can lower to:

```joy
dup * 1 +
```

The compiler must not insist on concatenative form when it is detrimental.
Indexed locals, SSA block parameters, and static environment records are
permitted internally. Naive S/K bracket abstraction is not an acceptance
requirement because it can cause substantial code and execution expansion.

The target machine uses Forth-like mechanisms—data stack, return stack, direct
calls, tail calls, and compact primitive operations—without implementing
Forth's textual compiler or mutable dictionary.

## 10. Runtime requirements

### 10.1 Core invariants

- The VM core must not allocate memory.
- Code and immutable constants must be read-only during execution.
- All mutable storage must be supplied explicitly by the caller.
- Invalid images, stack exhaustion, type errors, arithmetic overflow, and
  unsupported operations must return stable statuses.
- The VM must not panic for malformed untrusted image bytes after validation is
  complete.
- Execution must be deterministic given the same image, initial state, device
  inputs, and scheduling profile.
- No language exception may unwind across the firmware/VM boundary.

### 10.2 Stacks

The initial runtime has separate data and return stacks. Future traps or
higher-order combinators may add a continuation stack, but its storage and
maximum depth must also be explicit.

Image metadata must declare minimum stack capacities. The loader rejects an
image when the supplied target configuration cannot satisfy them.

### 10.3 Heap profiles

The runtime will support selectable heap profiles rather than one mandatory GC:

1. **No heap:** arithmetic/control programs only.
2. **Bounded arena:** allocation allowed up to a proven or configured ceiling;
   memory is reclaimed only when the whole invocation ends.
3. **Region/checkpoint:** application-defined phases reclaim whole regions.
4. **Copying collection:** compact moving collection using tagged indices, for
   devices that require long-running list/vector allocation.
5. **Hosted bridge:** optional values owned by a host runtime; not appropriate
   to FPGA images.

The first released embedded profile should prefer 32-bit indices rather than
native pointers. This makes images portable and permits heap relocation.

### 10.4 Device primitives

Device operations are statically numbered imports with declared stack effects,
capabilities, determinism classification, and worst-case status behavior.

Examples include GPIO access, timers, ADC sampling, message queues, bounded
serial I/O, and application-specific accelerators. Images must declare every
primitive they require. A loader must reject missing imports before execution.

## 11. Instruction and value format

The initial instruction is one little-endian 32-bit word:

- bits 31–24: opcode;
- bits 23–0: signed immediate/relative operand or unsigned address/index.

The initial 32-bit value tags are:

- `01`: signed 30-bit fixnum;
- `10`: immediate singleton such as true or false;
- `11`: static quotation/code address;
- `00`: reserved for linear-heap references.

Before declaring format version 1 stable, the product must specify:

- magic and format version;
- endianness and word size;
- section table and alignment;
- code and constant sections;
- function table with arity and stack effects;
- entry points;
- target feature/capability mask;
- required stack and heap sizes;
- device import table;
- optional symbols/source map;
- integrity checksum;
- validation rules for every opcode and reference.

## 12. Host compiler requirements

The compiler pipeline must eventually:

1. Accept a pinned Shen/KLambda version or a documented normalized input.
2. Select an explicit target profile.
3. Report every unsupported construct before emitting an image.
4. Resolve global calls and primitive identities statically where possible.
5. Perform lambda lifting and closure conversion.
6. Specialize higher-order functions when bounded call sites are known.
7. Lower expressions into a verified control-flow/SSA representation.
8. Schedule SSA values into Joy-style stack operations and indexed locals.
9. Preserve proper tail calls.
10. Infer or conservatively calculate stack and heap requirements.
11. Emit a deterministic image: identical input and toolchain produce identical
    bytes.
12. Validate its own emitted image before reporting success.
13. Produce a human-readable resource and capability report.

Compilation failures must identify the function and source construct where
possible, not merely an internal opcode.

## 13. FPGA requirements

The instruction set must permit a simple multi-cycle implementation with:

- code ROM or block RAM;
- data-stack and return-stack RAM;
- top-of-stack registers;
- a program counter and bounded stack pointers;
- deterministic decode;
- no dependency on executable memory or self-modifying code;
- code references represented as image addresses;
- heap references represented as indices rather than host pointers.

An RTL implementation is conformant only when it passes common image vectors
and cycle-independent execution traces against the Odin VM. Timing and
pipeline choices are implementation-specific; architectural state transitions
must match.

## 14. Microcontroller requirements

- The core must be usable without an OS.
- Static code and constants should be placeable in flash/ROM.
- Runtime state must fit caller-provided RAM regions.
- The implementation must not require dynamic linking or executable RAM.
- Interrupt integration and concurrency remain outside the VM unless a target
  profile explicitly specifies them.
- A firmware integrator must be able to set an instruction/fuel budget and
  regain control predictably.
- Optional tracing must compile out of production builds.

Odin is the primary executable specification. If a target is not supported by
the Odin compiler, a small C, Rust, Zig, or assembly implementation may be
provided against the same conformance vectors.

## 15. Security and robustness

- Treat image bytes as untrusted until fully validated.
- Check all code targets, section ranges, arithmetic during loading, stack
  effects, function IDs, quotation addresses, heap indices, and import IDs.
- Prevent integer wraparound in bounds and allocation calculations.
- Provide an instruction/fuel limit for untrusted or cooperative execution.
- Device primitives must validate addresses and lengths independently.
- Production configurations must be able to disable debugging and introspection
  sections.
- Malformed input must not produce arbitrary memory access.

Cryptographic signing is not required initially, but the format must reserve a
way to authenticate images externally.

## 16. Tooling and developer experience

Required host commands at the first usable compiler milestone:

```text
shen-joy compile --profile PROFILE INPUT --output IMAGE
shen-joy inspect IMAGE
shen-joy validate IMAGE
shen-joy run IMAGE [--entry NAME] [--fuel N]
```

`inspect` should report format version, functions, imports, feature mask,
maximum stack requirements, heap requirement, code size, constant size, and
debug metadata presence.

Builds and tests use the pinned Nix flake. The lock file and Odin source
revision are product inputs and must remain committed.

## 17. Verification requirements

### 17.1 Unit and property tests

- encode/decode round trips for every instruction and value type;
- arithmetic boundaries and overflow;
- stack and return-stack exhaustion;
- all branch, call, tail-call, return, quotation, and error paths;
- malformed image rejection;
- deterministic resource calculation;
- heap profile invariants when heaps are introduced.

### 17.2 Differential tests

For each supported Shen feature, compile source through the host pipeline and
compare results with the pinned reference Shen implementation. Tests must cover
normal results, tail recursion, boundary values, traps, resource limits, and
device primitive mocks.

Generated well-typed programs should supplement handwritten cases. Random
seeds and minimized failures must be reproducible.

### 17.3 Cross-implementation conformance

The same checked-in image fixtures must run on the Odin VM and every MCU/RTL
implementation. Conformance compares final values, statuses, externally
observable primitive traces, and architectural checkpoints.

## 18. Performance requirements

Initial performance work must report measurements rather than promise a fixed
speedup. Reports include hardware, OS/firmware target, compiler revision,
image fingerprint, build mode, sample count, and workload checksum.

Before the first embedded release:

- VM dispatch must perform no dynamic allocation;
- common arithmetic and branch instructions should require one instruction
  fetch each;
- static calls must avoid symbol/dictionary lookup;
- tail calls must not grow the return stack;
- production images must omit unused opcode families and device imports where
  practical;
- an instruction/fuel count must be available for portable comparisons.

Native AOT or FPGA pipeline performance gates will be set only after the
portable semantics and representative applications exist.

## 19. Milestones and acceptance criteria

### M0 — Repository and semantic seed

- Independent Git repository and pinned Nix flake.
- Allocation-free 32-bit Odin VM.
- Fixnums, booleans, arithmetic, comparisons, branches, calls, tail calls,
  static quotations, `i`, and explicit statuses.
- Unit tests and packaged demo pass.

**Current status:** implemented. The demo executes `6 dup * 1 +` and returns
`37`.

### M1 — Versioned image and validator

- Binary image header and sections.
- Encoder, decoder, inspector, and structural validator.
- Function metadata, entry points, imports, and resource declarations.
- Corrupt/truncated/adversarial fixtures are rejected without panic.
- Round-trip output is deterministic.

### M2 — First Shen-to-image path

- Accept a documented normalized KLambda subset.
- Compile at least arithmetic, conditionals, first-order calls, and tail
  recursion.
- Demonstrate stack/Joy lowering and indexed-local fallback.
- Differentially pass representative programs against Shen-Forth or another
  pinned Shen reference.
- Produce a resource report for every successful image.

### M3 — Bounded data and embedded application

- Add lists and bounded vectors using a selected heap profile.
- Add statically declared mocked device primitives.
- Compile and run one realistic Shen-derived application, such as a protocol
  state machine or sensor decision controller.
- Demonstrate deterministic failure when configured memory is insufficient.

### M4 — Microcontroller deployment

- Select and document a concrete MCU/toolchain.
- Boot without an OS and execute a checked image from flash.
- Exercise at least one real device primitive.
- Record flash, RAM, stack, heap, instruction count, and timing.
- Match the Odin reference trace.

### M5 — FPGA reference implementation

- Implement the stable VM subset in synthesizable RTL.
- Run common conformance images in simulation.
- Demonstrate on a selected FPGA board or a reproducible simulator.
- Report logic, BRAM, maximum clock, cycles, and trace agreement.

### M6 — Optimization

- Add profile-guided or static stack scheduling.
- Evaluate superinstructions and native AOT lowering.
- Preserve byte-for-byte semantic conformance.
- Establish workload-specific performance gates based on measured baselines.

## 20. Release gates

A release claiming embedded Shen execution must not ship until:

1. The image format used by that release is versioned and completely
   documented.
2. The loader validates every externally supplied reference and bound.
3. The deployed Shen subset and unsupported features are documented.
4. Differential tests cover every advertised language feature.
5. Stack, heap, and import requirements are recorded in each image.
6. Resource exhaustion returns a documented status.
7. At least one nontrivial Shen-derived program runs end to end.
8. Reproducible build and conformance commands pass from a clean checkout.
9. Performance and memory claims are backed by checked evidence.

An FPGA release additionally requires RTL simulation against common
conformance vectors. A hardware-board claim requires evidence from that board.

## 21. Risks and mitigations

### Combinator or stack-code expansion

Pure bracket abstraction or excessive stack shuffling may inflate programs.
Use SSA analysis, indexed locals, lambda lifting, specialization budgets, and
measured lowering decisions.

### Shen semantic scope creep

Full Shen would overwhelm small targets. Make capabilities explicit, reject
unsupported features during compilation, and grow profiles only through
measured applications.

### Garbage-collection complexity

Do not select one GC for every target. Begin with no-heap and bounded-arena
profiles; add a compact collector only when a real workload requires it.

### Odin target availability

Keep the machine specification language-neutral and publish conformance
vectors. Odin remains the oracle even when a device needs another
implementation language.

### FPGA divergence

Maintain one versioned architectural specification and compare instruction
traces at defined checkpoints. Do not add undocumented RTL-only behavior.

### Premature native optimization

Do not begin with JIT or register allocation. Stabilize image semantics and
representative workloads first; add AOT/native execution behind the same
conformance suite.

## 22. Open product decisions

These decisions must be resolved using representative programs before their
corresponding milestone:

- normalized Shen/KLambda input representation for M2;
- exact function metadata and stack-effect encoding;
- whether relative or absolute call targets are canonical;
- first heap profile and object layout;
- closure capability permitted in the initial data profile;
- first MCU and FPGA targets;
- device primitive ABI;
- instruction fuel and preemption semantics;
- debugging/source-map format;
- stable image-format compatibility policy.

## 23. Immediate next work

1. Implement the M1 image header, serializer, decoder, and validator.
2. Add structural validation before VM execution, including opcode and target
   checks.
3. Specify functions, stack effects, entry points, and fuel behavior.
4. Choose a normalized, small KLambda input for the first compiler slice.
5. Compile and differentially test `square+1`, conditional selection, and a
   tail-recursive numeric function.
