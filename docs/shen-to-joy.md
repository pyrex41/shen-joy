# Shen to Joy

Joy is useful here because concatenative programs expose stack effects and
make many variable operations compile-time rearrangements.  For example:

```shen
(defun square+1 (X) (+ (* X X) 1))
```

has the Joy-shaped body:

```joy
dup * 1 +
```

That is attractive for a small CPU or FPGA: `dup` can be a register rename,
and a later native backend can keep the intermediate value off memory.

Full Joy is not the target language.  Full Joy treats quotations as ordinary
list data and provides higher-order combinators that can construct and inspect
them dynamically.  Implementing those semantics would reintroduce much of
the allocation, closure, and garbage-collection machinery this project is
trying to bound.

Instead, quotations in the embedded profile are immutable code addresses.
The `quote` instruction creates a tagged code reference and `i` invokes it.
Image validation proves that quotation targets are instruction boundaries.
Future combinators such as `ifte`, `dip`, and `map` will use static quotation
references and explicit continuation records.

## Why not bracket abstraction everywhere?

Arbitrary lambda terms can be translated to S/K/B/C combinators, but naive
bracket abstraction can greatly expand code and execution count.  Deep stack
shuffling has similar costs.  The host compiler therefore uses a hybrid IR:

- stack values and Joy operations where effects are clear;
- indexed locals at control-flow joins or where values have distant uses;
- static calls after lambda lifting;
- explicit environments only for closures that survive specialization.

SSA provides a useful internal representation for deciding which values stay
on the stack, become locals, or are captured.  It is a compiler tool, not part
of the device image.

## Initial Shen subset

- fixnum and boolean constants;
- first-order functions with known arities;
- `if`, sequencing, and tail recursion;
- arithmetic and comparisons;
- static quotations introduced by the compiler;
- no runtime `eval`, symbol rebinding, reader, or interactive definitions.

Bounded lists/vectors and device primitives are selectable capabilities.
Restricted closures and traps remain explicit future capabilities.

## Normalized input accepted by the compiler

The M2 frontend deliberately accepts normalized KLambda-style s-expressions,
not arbitrary Shen source. A file has one `program` form containing imports,
functions, and zero-arity entries:

```lisp
(program
  (import adc-read 1 0 1 effectful)
  (function square+1 (X) (+ (* X X) 1))
  (function main () (square+1 6))
  (entry main))
```

Expressions are signed 30-bit integers, `true`, `false`, `nil`, variables,
`if`, `do`, `let`, `+`, `-`, `*`, `=`, `<`, static first-order calls,
`cons`, `head`, `tail`, `nil?`, fixed-length `vector`, `vector-get`,
`vector-set`, and `(device NAME ARG...)`. Imports declare numeric identity,
input/output count, and `deterministic` or `effectful` classification.
The normalized input is the output of an upstream Shen typechecking/lowering
step; this compiler does not contain the Shen typechecker. Equality is scalar
(fixnums, booleans, and static quotations); structural list/vector equality is
unsupported and returns an explicit status if invalid normalized input uses it.

Every recursive call must be in tail position. For a finite conservative
return-stack proof, non-tail calls may only target an earlier function in the
file; helpers therefore precede callers. Functions have at most 16 parameters,
programs 128 functions, normalized trees 4096 nodes, and generated images
16384 instructions. These are host compiler limits with named diagnostics,
not device-side parser behavior.

For version 1's invocation arena, allocation sites must remain in an entry
function and cannot be reached through a call or recursion. This intentionally
conservative rule makes the summed arena ceiling sound. Programs needing
repeated allocation require a later region/copying profile and are rejected.

Repeated operands such as `(* X X)` are statically scheduled as a `dup-mul`
superinstruction. `let` values and distant uses use indexed frame locals.
The compiler rejects unknown names, wrong arities, forward/non-tail recursive
calls, runtime evaluation, closures, strings, symbols, traps, arbitrary
quotations, and dynamic globals before image emission.
