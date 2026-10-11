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

## Kernel baseline: ShenOSKernel 42.2

The subset is defined relative to the community ShenOSKernel 42.2
(`Shen-Language/shen-sources` tag `shen-42.2`). That is the kernel shipped by
shen-scheme 0.50, which is also the differential reference; see
[PROVENANCE.md](../PROVENANCE.md). The Tarver S42.0 lineage is not used.
shen-joy runs no kernel code. A kernel change matters here only if it changes
the KLambda that a host lowerer receives for subset programs, or the meaning
of the operations the subset keeps.

| Kernel change | Status in shen-joy | Reason |
|---|---|---|
| 42.0 `update-lambda-table` invalidates a stale `lambda-form` on redefinition with zero or unknown arity | Excluded (not applicable) | The device has no function table, `fn`, partial application or dynamic application. The host compiler rejects a second definition of a name (`duplicate function`), so redefinition cannot occur. |
| 42.0 factoriser groups more repeated selectors | Excluded | `*factorise?*` is off by default in 42.2. Unfactorised definitions in the subset compile to the same `cond`/`if` KLambda as on 41.2. With `(factorise +)`, the kernel emits `(let GoToN (freeze E) ... (thaw GoToN))` continuations. `freeze`/`thaw` are closures, so a lowerer must reject them. Lowering that specific shape to a join point is possible future host-side work; the device needs no change. |
| 41.3 `input+` became a macro | Excluded | Streams and input are outside the subset. |
| 42.1 source-form handlers, `shen.macroexpand-h` 4th argument, `shen.try-parse` returning parsed forms | Excluded | They run in the Shen reader and macro expander on the host, before KLambda exists. shen-joy contains no Shen reader. The device never reads source (see AGENTS.md). |
| 42.1 `read`/`lineread` EOF fix | Excluded from the device; the host analogue holds | The device has no reader. shen-joy's own `.sjk` reader accepts a final form that has no trailing newline (verified when this baseline was adopted). |
| 42.1 `namespaces` and `type-annotations` extensions; 42.2 `externals`/`with-externals` evaluation | Excluded | Symbols, packages and evaluated symbol lists are not values in the subset. The normalized form has no package syntax. |
| 41.1 precompiled `stlib.kl` | Excluded | No standard library runs on the device. A call to an StLib function is an unknown name and is rejected. |

**Subset semantics are unchanged.** None of the changes above affect
first-order fixnum/boolean code, `let`, `if`/`cond`, `do`, tail calls, or the
list and absvector primitives that the `arena` profile models. With default
settings, the KLambda that 42.2 emits for the subset fixtures
(`tests/differential.shen`, and Yggdrasil's `tests/joy-sum.shen` and
`tests/fib.shen`) has the same shape as the S42.0 output checked in at
Yggdrasil's `tests/fib.kl`. Only the gensym numbers differ. The differential
programs give the same results as on the 41.2 reference (`92` and `51`). The existing differences from full Shen still apply:
signed 30-bit fixnums instead of Shen numbers, scalar-only `=`, and a bounded
arena. They are not kernel-version dependent.

A real 42.2 shake through Yggdrasil is not yet available, because Yggdrasil
still vendors S42.0 (pyrex41/yggdrasil#32). When it moves to 42.2, its `joy`
lowerer must keep rejecting factorised `freeze`/`thaw` continuations. The
pattern compiler also emits `and` tests for multi-column patterns, for example
`(and (cons? V) (= 1 W))`. The lowerer must lower these or reject them with
capability status 3. This is not new in 42.2.

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
