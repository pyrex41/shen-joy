package main

import "core:testing"

compile_and_run :: proc(source: string, data: []Value, returns: []int, heap: []Value) -> (Result, Compile_Result) {
	output: Compile_Output
	compiled := compile_normalized(transmute([]u8)source, &output)
	if compiled.status != .Ok { return Result{status=.Bad_Image}, compiled }
	spec := compiled_image_spec(&output)
	buffer: [131072]u8
	n, encoded := encode_image(&spec, buffer[:]); if encoded != .Ok { return Result{status=encoded}, compiled }
	image, validated := decode_and_validate_image(buffer[:n]); if validated != .Ok { return Result{status=validated}, compiled }
	entry, found := image_entry_address(&image); if !found { return Result{status=.Bad_Image}, compiled }
	machine := Machine{data=data, returns=returns, heap=heap, constants=output.constants[:output.constant_count], fuel=100000}
	return run(output.code[:output.code_count], &machine, entry), compiled
}

@(test)
compiler_arithmetic_joy_and_call :: proc(t: ^testing.T) {
	source := `(program
  (function square+1 (X) (+ (* X X) 1))
  (function main () (square+1 6))
  (entry main))`
	data: [256]Value; returns: [64]int; heap: [1]Value
	result, compiled := compile_and_run(source, data[:], returns[:], heap[:])
	n, fix := from_fixnum(result.value)
	testing.expect(t, compiled.status == .Ok && result.status == .Ok && fix && n == 37)
	output: Compile_Output; _ = compile_normalized(transmute([]u8)source, &output)
	found_superinstruction := false
	for instruction in output.code[:output.code_count] { if Opcode(u8(instruction>>24)) == .Dup_Mul { found_superinstruction = true } }
	testing.expect(t, found_superinstruction)
}

@(test)
compiler_conditional_tail_recursion_and_locals :: proc(t: ^testing.T) {
	source := `(program
  (function sum-loop (N Acc)
    (if (= N 0) Acc (sum-loop (- N 1) (+ Acc N))))
  (function main () (let Limit 10 (sum-loop Limit 0)))
  (entry main))`
	data: [512]Value; returns: [64]int; heap: [1]Value
	result, compiled := compile_and_run(source, data[:], returns[:], heap[:])
	n, fix := from_fixnum(result.value)
	testing.expect(t, compiled.status == .Ok && result.status == .Ok && fix && n == 55)
}

@(test)
compiler_rejects_unsupported_and_bad_arity :: proc(t: ^testing.T) {
	output: Compile_Output
	unsupported := `(program (function main () (eval 1)) (entry main))`
	result := compile_normalized(transmute([]u8)unsupported, &output)
	testing.expect(t, result.status == .Unsupported_Construct && result.construct == "eval")
	bad_call := `(program (function f (X) X) (function main () (f 1 2)) (entry main))`
	result = compile_normalized(transmute([]u8)bad_call, &output)
	testing.expect(t, result.status == .Invalid_Program)
}
