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
