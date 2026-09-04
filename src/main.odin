package main

import "core:fmt"
import "core:os"

demo :: proc() -> (Value, Status) {
	// Joy: 6 dup * 1 +
	program := [?]Instruction{
		encode(.Push, 6),
		encode(.Dup),
		encode(.Mul),
		encode(.Push, 1),
		encode(.Add),
		encode(.Halt),
	}
	data: [16]Value
	returns: [8]int
	machine := Machine{data=data[:], returns=returns[:]}
	result := run(program[:], &machine)
	return result.value, result.status
}

main :: proc() {
	if len(os.args) == 2 && os.args[1] == "--demo" {
		value, status := demo()
		if status != .Ok { fmt.println("error: ", status); return }
		n, ok := from_fixnum(value)
		if !ok { fmt.println("error: non-fixnum result"); return }
		fmt.println(n)
		return
	}
	fmt.println("usage: shen-joy --demo")
}
