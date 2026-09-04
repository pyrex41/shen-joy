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

Lists, vectors, restricted closures, traps, and device primitives will be
added as separately selectable target capabilities.
