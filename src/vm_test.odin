package main

import "core:testing"

@(test)
joy_arithmetic :: proc(t: ^testing.T) {
	value, status := demo()
	n, fix := from_fixnum(value)
	testing.expect(t, status == .Ok)
	testing.expect(t, fix && n == 37)
}

@(test)
static_quotation_i :: proc(t: ^testing.T) {
	// Main quotes word at address 3 and executes it; the word adds two.
	program := [?]Instruction{
		encode(.Push, 40), encode(.Quote, 3), encode(.I),
		encode(.Push, 2), encode(.Add), encode(.Return),
		encode(.Halt),
	}
	// I returns to address 3, which would recurse into the quotation.  Put the
	// continuation before the quotation and jump over its body instead.
	program = [?]Instruction{
		encode(.Push, 40), encode(.Quote, 4), encode(.I), encode(.Halt),
		encode(.Push, 2), encode(.Add), encode(.Return),
	}
	data: [8]Value
	returns: [4]int
	m := Machine{data=data[:], returns=returns[:]}
	result := run(program[:], &m)
	n, ok := from_fixnum(result.value)
	testing.expect(t, result.status == .Ok)
	testing.expect(t, ok && n == 42)
}

@(test)
resource_limits_are_statuses :: proc(t: ^testing.T) {
	program := [?]Instruction{encode(.Push, 1), encode(.Push, 2), encode(.Halt)}
	data: [1]Value
	returns: [1]int
	m := Machine{data=data[:], returns=returns[:]}
	result := run(program[:], &m)
	testing.expect(t, result.status == .Stack_Limit)
}

@(test)
arithmetic_boundaries_overflow_and_types :: proc(t: ^testing.T) {
	max_value, max_ok := to_fixnum(FIXNUM_MAX); min_value, min_ok := to_fixnum(FIXNUM_MIN)
	_, above := to_fixnum(FIXNUM_MAX+1); _, below := to_fixnum(FIXNUM_MIN-1)
	testing.expect(t, max_ok && min_ok && !above && !below)
	max_round, max_fix := from_fixnum(max_value); min_round, min_fix := from_fixnum(min_value)
	testing.expect(t, max_fix && min_fix && i64(max_round)==FIXNUM_MAX && i64(min_round)==FIXNUM_MIN)
	program := [?]Instruction{encode(.Push, 1000000), encode(.Push, 1000000), encode(.Mul), encode(.Halt)}
	data: [8]Value; returns: [3]int; m := Machine{data=data[:], returns=returns[:]}
	testing.expect(t, run(program[:], &m).status == .Arithmetic_Overflow)
	type_program := [?]Instruction{encode(.Push_True), encode(.Push, 1), encode(.Add), encode(.Halt)}
	testing.expect(t, run(type_program[:], &m).status == .Type_Error)
}

@(test)
fuel_and_return_limits_are_statuses :: proc(t: ^testing.T) {
	loop := [?]Instruction{encode(.Jump, -1)}
	data: [4]Value; returns: [2]int; m := Machine{data=data[:], returns=returns[:], fuel=5}
	result := run(loop[:], &m)
	testing.expect(t, result.status == .Fuel_Exhausted && m.steps == 5)
	call := [?]Instruction{encode(.Call, 2), encode(.Halt), encode(.Return)}
	m.fuel = 0
	testing.expect(t, run(call[:], &m).status == .Return_Limit)
}

@(test)
deterministic_generated_arithmetic :: proc(t: ^testing.T) {
	seed := u32(0x5eed1234)
	for _ in 0..<256 {
		seed = seed*1664525+1013904223; a := i32(seed%2001)-1000
		seed = seed*1664525+1013904223; b := i32(seed%2001)-1000
		program := [?]Instruction{encode(.Push,a),encode(.Push,b),encode(.Mul),encode(.Push,a),encode(.Add),encode(.Halt)}
		data: [8]Value; returns: [3]int; m := Machine{data=data[:],returns=returns[:]}
		result := run(program[:],&m); actual, ok := from_fixnum(result.value)
		testing.expect(t, result.status==.Ok && ok && i64(actual)==i64(a)*i64(b)+i64(a))
	}
}
