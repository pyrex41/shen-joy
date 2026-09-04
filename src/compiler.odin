package main

import "core:strconv"

MAX_NODES     :: 4096
MAX_FUNCTIONS :: 128
MAX_PARAMS    :: 16
MAX_CODE      :: 16384
MAX_CONSTANTS :: 1024
MAX_FIXUPS    :: 2048
MAX_LOCALS    :: 64
MAX_IMPORTS   :: 64

Node_Kind :: enum u8 { Atom, List }

Node :: struct {
	kind: Node_Kind,
	start: int,
	end: int,
	first: int,
	next: int,
}

Parser :: struct {
	source: []u8,
	position: int,
	nodes: [MAX_NODES]Node,
	count: int,
	error_offset: int,
}

Compile_Status :: enum u8 {
	Ok,
	Syntax_Error,
	Unsupported_Construct,
	Unknown_Name,
	Limit_Exceeded,
	Invalid_Program,
}

Compile_Result :: struct {
	status: Compile_Status,
	offset: int,
	function_name: string,
	construct: string,
}

skip_space :: proc(p: ^Parser) {
	for p.position < len(p.source) {
		b := p.source[p.position]
		if b == ';' {
			for p.position < len(p.source) && p.source[p.position] != '\n' { p.position += 1 }
		} else if b == ' ' || b == '\t' || b == '\r' || b == '\n' {
			p.position += 1
		} else { break }
	}
}

new_node :: proc(p: ^Parser, node: Node) -> (int, bool) {
	if p.count >= MAX_NODES { p.error_offset = p.position; return 0, false }
	index := p.count; p.nodes[index] = node; p.count += 1
	return index, true
}

parse_node :: proc(p: ^Parser) -> (int, bool) {
	skip_space(p)
	if p.position >= len(p.source) { p.error_offset = p.position; return 0, false }
	if p.source[p.position] == '(' {
		start := p.position; p.position += 1
		index, ok := new_node(p, Node{kind=.List, start=start, first=-1, next=-1}); if !ok { return 0, false }
		last := -1
		for {
			skip_space(p)
			if p.position >= len(p.source) { p.error_offset = start; return 0, false }
			if p.source[p.position] == ')' { p.position += 1; p.nodes[index].end = p.position; return index, true }
			child, child_ok := parse_node(p); if !child_ok { return 0, false }
			if last < 0 { p.nodes[index].first = child } else { p.nodes[last].next = child }
			last = child
		}
	}
	if p.source[p.position] == ')' { p.error_offset = p.position; return 0, false }
	start := p.position
	for p.position < len(p.source) {
		b := p.source[p.position]
		if b == '(' || b == ')' || b == ' ' || b == '\t' || b == '\r' || b == '\n' || b == ';' { break }
		p.position += 1
	}
	if start == p.position { p.error_offset = start; return 0, false }
	return new_node(p, Node{kind=.Atom, start=start, end=p.position, first=-1, next=-1})
}

node_text :: proc(p: ^Parser, index: int) -> string {
	if index < 0 || index >= p.count { return "" }
	n := p.nodes[index]
	return string(p.source[n.start:n.end])
}

nth_child :: proc(p: ^Parser, list: int, wanted: int) -> int {
	if list < 0 || list >= p.count || p.nodes[list].kind != .List { return -1 }
	child := p.nodes[list].first
	for i in 0..<wanted { if child < 0 { return -1 }; child = p.nodes[child].next }
	return child
}

child_count :: proc(p: ^Parser, list: int) -> int {
	count := 0; child := nth_child(p, list, 0)
	for child >= 0 { count += 1; child = p.nodes[child].next }
	return count
}

Function_IR :: struct {
	name_node: int,
	params_node: int,
	body_node: int,
	address: int,
	arity: int,
	locals: int,
	max_stack: int,
	heap_words: u32,
}

Import_IR :: struct {
	name_node: int,
	primitive_id: u32,
	inputs: int,
	outputs: int,
	flags: u32,
}

Fixup :: struct { code_index: int, function_index: int }

Compile_Output :: struct {
	code: [MAX_CODE]Instruction,
	code_count: int,
	constants: [MAX_CONSTANTS]Value,
	constant_count: int,
	function_words: [MAX_FUNCTIONS*FUNCTION_WORDS]u32,
	function_count: int,
	entry_words: [MAX_FUNCTIONS*ENTRY_WORDS]u32,
	entry_count: int,
	import_words: [MAX_IMPORTS*IMPORT_WORDS]u32,
	import_count: int,
	fixups: [MAX_FIXUPS]Fixup,
	fixup_count: int,
	resources: [RESOURCE_WORDS]u32,
	heap_words: u32,
}

Compiler :: struct {
	parser: Parser,
	functions: [MAX_FUNCTIONS]Function_IR,
	function_count: int,
	imports: [MAX_IMPORTS]Import_IR,
	import_count: int,
	output: Compile_Output,
	current_function: int,
	stack_depth: int,
	max_stack: int,
	local_names: [MAX_LOCALS]int,
	local_slots: [MAX_LOCALS]int,
	local_count: int,
	next_local: int,
	result: Compile_Result,
}

name_hash :: proc(name: string) -> u32 {
	h := u32(2166136261)
	for b in name { h = (h~u32(b))*u32(16777619) }
	return h
}

fail :: proc(c: ^Compiler, status: Compile_Status, node: int, construct: string) -> bool {
	c.result.status = status; c.result.construct = construct
	if node >= 0 && node < c.parser.count { c.result.offset = c.parser.nodes[node].start }
	if c.current_function >= 0 && c.current_function < c.function_count {
		c.result.function_name = node_text(&c.parser, c.functions[c.current_function].name_node)
	}
	return false
}

emit :: proc(c: ^Compiler, op: Opcode, operand: i32 = 0, effect: int = 0) -> (int, bool) {
	if c.output.code_count >= MAX_CODE { return 0, fail(c, .Limit_Exceeded, -1, "code limit") }
	if c.stack_depth+effect < 0 { return 0, fail(c, .Invalid_Program, -1, "stack effect") }
	index := c.output.code_count; c.output.code[index] = encode(op, operand); c.output.code_count += 1
	c.stack_depth += effect; if c.stack_depth > c.max_stack { c.max_stack = c.stack_depth }
	return index, true
}

find_function :: proc(c: ^Compiler, name_node: int) -> int {
	name := node_text(&c.parser, name_node)
	for i in 0..<c.function_count { if node_text(&c.parser, c.functions[i].name_node) == name { return i } }
	return -1
}

find_import :: proc(c: ^Compiler, name_node: int) -> int {
	name := node_text(&c.parser, name_node)
	for i in 0..<c.import_count { if node_text(&c.parser, c.imports[i].name_node) == name { return i } }
	return -1
}

find_local :: proc(c: ^Compiler, name_node: int) -> int {
	name := node_text(&c.parser, name_node)
	for reverse_index in 0..<c.local_count {
		i := c.local_count-1-reverse_index
		if node_text(&c.parser, c.local_names[i]) == name { return c.local_slots[i] }
	}
	return -1
}

intern_constant :: proc(c: ^Compiler, value: Value) -> (int, bool) {
	for existing, i in c.output.constants[:c.output.constant_count] { if existing == value { return i, true } }
	if c.output.constant_count >= MAX_CONSTANTS { return 0, false }
	index := c.output.constant_count; c.output.constants[index] = value; c.output.constant_count += 1
	return index, true
}

same_atom :: proc(c: ^Compiler, a, b: int) -> bool {
	return a >= 0 && b >= 0 && c.parser.nodes[a].kind == .Atom && c.parser.nodes[b].kind == .Atom && node_text(&c.parser, a) == node_text(&c.parser, b)
}

compile_expr :: proc(c: ^Compiler, node: int, tail: bool) -> bool {
	if node < 0 || node >= c.parser.count { return fail(c, .Syntax_Error, node, "missing expression") }
	n := c.parser.nodes[node]
	if n.kind == .Atom {
		text := node_text(&c.parser, node)
		if text == "true" { _, ok := emit(c, .Push_True, effect=1); return ok }
		if text == "false" { _, ok := emit(c, .Push_False, effect=1); return ok }
		if text == "nil" { _, ok := emit(c, .Nil, effect=1); return ok }
		if number, ok := strconv.parse_i64(text); ok {
			value, fits := to_fixnum(number); if !fits { return fail(c, .Unsupported_Construct, node, "integer outside signed 30-bit fixnum") }
			if number >= -0x800000 && number <= 0x7fffff { _, emitted := emit(c, .Push, i32(number), 1); return emitted }
			constant, room := intern_constant(c, value); if !room { return fail(c, .Limit_Exceeded, node, "constant limit") }
			_, emitted := emit(c, .Push_Const, i32(constant), 1); return emitted
		}
		slot := find_local(c, node); if slot < 0 { return fail(c, .Unknown_Name, node, text) }
		_, ok := emit(c, .Load_Local, i32(slot), 1); return ok
	}
	head := nth_child(&c.parser, node, 0); if head < 0 || c.parser.nodes[head].kind != .Atom { return fail(c, .Syntax_Error, node, "list head") }
	op_name := node_text(&c.parser, head)
	if op_name == "if" {
		if child_count(&c.parser, node) != 4 { return fail(c, .Syntax_Error, node, "if") }
		if !compile_expr(c, nth_child(&c.parser, node, 1), false) { return false }
		branch, ok := emit(c, .Jump_False, effect=-1); if !ok { return false }
		base_depth := c.stack_depth
		if !compile_expr(c, nth_child(&c.parser, node, 2), tail) { return false }
		then_depth := c.stack_depth
		jump, jok := emit(c, .Jump); if !jok { return false }
		else_at := c.output.code_count; c.output.code[branch] = encode(.Jump_False, i32(else_at-(branch+1)))
		c.stack_depth = base_depth
		if !compile_expr(c, nth_child(&c.parser, node, 3), tail) { return false }
		if c.stack_depth != then_depth { return fail(c, .Invalid_Program, node, "if branch stack mismatch") }
		c.output.code[jump] = encode(.Jump, i32(c.output.code_count-(jump+1)))
		return true
	}
	if op_name == "do" {
		count := child_count(&c.parser, node); if count < 2 { return fail(c, .Syntax_Error, node, "do") }
		for i in 1..<count {
			if !compile_expr(c, nth_child(&c.parser, node, i), tail && i == count-1) { return false }
			if i != count-1 { if _, ok := emit(c, .Drop, effect=-1); !ok { return false } }
		}
		return true
	}
	if op_name == "let" {
		if child_count(&c.parser, node) != 4 { return fail(c, .Syntax_Error, node, "let") }
		name_node := nth_child(&c.parser, node, 1); if c.parser.nodes[name_node].kind != .Atom { return fail(c, .Syntax_Error, name_node, "let name") }
		if c.local_count >= MAX_LOCALS { return fail(c, .Limit_Exceeded, node, "local limit") }
		if !compile_expr(c, nth_child(&c.parser, node, 2), false) { return false }
		slot := c.next_local; c.next_local += 1
		if _, ok := emit(c, .Store_Local, i32(slot), -1); !ok { return false }
		old_count := c.local_count; c.local_names[c.local_count] = name_node; c.local_slots[c.local_count] = slot; c.local_count += 1
		ok := compile_expr(c, nth_child(&c.parser, node, 3), tail)
		c.local_count = old_count
		return ok
	}
	if op_name == "+" || op_name == "-" || op_name == "*" || op_name == "=" || op_name == "<" || op_name == "cons" {
		if child_count(&c.parser, node) != 3 { return fail(c, .Syntax_Error, node, op_name) }
		a, b := nth_child(&c.parser, node, 1), nth_child(&c.parser, node, 2)
		if !compile_expr(c, a, false) { return false }
		if same_atom(c, a, b) && op_name == "*" { _, ok := emit(c, .Dup_Mul); return ok }
		if same_atom(c, a, b) { if _, ok := emit(c, .Dup, effect=1); !ok { return false } } else if !compile_expr(c, b, false) { return false }
		op := Opcode.Add
		switch op_name { case "+": op=.Add; case "-": op=.Sub; case "*": op=.Mul; case "=": op=.Eq; case "<": op=.Lt; case "cons": op=.Cons }
		if op == .Cons { c.output.heap_words += 3 }
		_, ok := emit(c, op, effect=-1); return ok
	}
	if op_name == "head" || op_name == "tail" || op_name == "nil?" {
		if child_count(&c.parser, node) != 2 || !compile_expr(c, nth_child(&c.parser, node, 1), false) { return false }
		op := Opcode.Head; if op_name == "tail" { op=.Tail } else if op_name == "nil?" { op=.Is_Nil }
		_, ok := emit(c, op); return ok
	}
	if op_name == "vector" {
		if child_count(&c.parser, node) != 2 { return fail(c, .Syntax_Error, node, "vector") }
		length_node := nth_child(&c.parser, node, 1); length, ok := strconv.parse_i64(node_text(&c.parser, length_node))
		if !ok || length < 0 || length > 0xffffff { return fail(c, .Unsupported_Construct, length_node, "bounded vector length") }
		if u64(c.output.heap_words)+u64(length)+1 > u64(max(u32)) { return fail(c, .Limit_Exceeded, node, "heap analysis overflow") }
		c.output.heap_words += u32(length)+1
		_, emitted := emit(c, .Vector_New, i32(length), 1); return emitted
	}
	if op_name == "vector-get" {
		if child_count(&c.parser, node) != 3 || !compile_expr(c, nth_child(&c.parser, node, 1), false) || !compile_expr(c, nth_child(&c.parser, node, 2), false) { return false }
		_, ok := emit(c, .Vector_Get, effect=-1); return ok
	}
	if op_name == "vector-set" {
		if child_count(&c.parser, node) != 4 || !compile_expr(c, nth_child(&c.parser, node, 1), false) || !compile_expr(c, nth_child(&c.parser, node, 2), false) || !compile_expr(c, nth_child(&c.parser, node, 3), false) { return false }
		_, ok := emit(c, .Vector_Set, effect=-2); return ok
	}
	if op_name == "device" {
		name := nth_child(&c.parser, node, 1); import_index := find_import(c, name)
		if name < 0 || import_index < 0 { return fail(c, .Unknown_Name, node, "device import") }
		imp := c.imports[import_index]; arguments := child_count(&c.parser, node)-2
		if arguments != imp.inputs || imp.outputs != 1 { return fail(c, .Invalid_Program, node, "device stack effect") }
		for i in 0..<arguments { if !compile_expr(c, nth_child(&c.parser, node, i+2), false) { return false } }
		_, ok := emit(c, .Invoke, i32(imp.primitive_id), imp.outputs-imp.inputs)
		return ok
	}
	if op_name == "eval" || op_name == "lambda" || op_name == "freeze" || op_name == "trap-error" ||
	   op_name == "set" || op_name == "open" || op_name == "intern" || op_name == "quote" || op_name == "primitive" {
		return fail(c,.Unsupported_Construct,node,op_name)
	}
	// All remaining list heads are statically resolved first-order calls.
	function_index := find_function(c, head); if function_index < 0 { return fail(c, .Unknown_Name, head, op_name) }
	argument_count := child_count(&c.parser, node)-1
	if argument_count != c.functions[function_index].arity { return fail(c, .Invalid_Program, node, "call arity") }
	for i in 0..<argument_count { if !compile_expr(c, nth_child(&c.parser, node, i+1), false) { return false } }
	if !tail && function_index >= c.current_function { return fail(c, .Unsupported_Construct, node, "non-tail recursion or forward call") }
	if tail && function_index > c.current_function { return fail(c, .Unsupported_Construct, node, "forward tail call") }
	op := Opcode.Call; if tail { op = .Tail_Call }
	code_index, emitted := emit(c, op, 0, 1-argument_count); if !emitted { return false }
	if c.output.fixup_count >= MAX_FIXUPS { return fail(c, .Limit_Exceeded, node, "fixup limit") }
	c.output.fixups[c.output.fixup_count] = Fixup{code_index, function_index}; c.output.fixup_count += 1
	return true
}

count_lets :: proc(c: ^Compiler, node: int) -> int {
	if node < 0 || c.parser.nodes[node].kind == .Atom { return 0 }
	head := nth_child(&c.parser, node, 0); own := 0; if head >= 0 && node_text(&c.parser, head) == "let" { own = 1 }
	total := own; child := c.parser.nodes[node].first
	for child >= 0 { total += count_lets(c, child); child = c.parser.nodes[child].next }
	return total
}

compile_normalized :: proc(source: []u8, output: ^Compile_Output) -> Compile_Result {
	c := new(Compiler); defer free(c)
	c.current_function = -1; c.parser.source = source
	root, parsed := parse_node(&c.parser); if !parsed { return Compile_Result{status=.Syntax_Error, offset=c.parser.error_offset, construct="s-expression"} }
	skip_space(&c.parser); if c.parser.position != len(source) { return Compile_Result{status=.Syntax_Error, offset=c.parser.position, construct="trailing input"} }
	if node_text(&c.parser, nth_child(&c.parser, root, 0)) != "program" { return Compile_Result{status=.Invalid_Program, construct="program"} }
	child := nth_child(&c.parser, root, 1)
	for child >= 0 {
		head := nth_child(&c.parser, child, 0); kind := node_text(&c.parser, head)
		if kind == "function" {
			if child_count(&c.parser, child) != 4 || c.function_count >= MAX_FUNCTIONS { return Compile_Result{status=.Invalid_Program, offset=c.parser.nodes[child].start, construct="function"} }
			name, params, body := nth_child(&c.parser, child, 1), nth_child(&c.parser, child, 2), nth_child(&c.parser, child, 3)
			if name < 0 || params < 0 || c.parser.nodes[name].kind != .Atom || c.parser.nodes[params].kind != .List { return Compile_Result{status=.Syntax_Error, offset=c.parser.nodes[child].start, construct="function"} }
			arity := child_count(&c.parser, params); if arity > MAX_PARAMS { return Compile_Result{status=.Limit_Exceeded, offset=c.parser.nodes[params].start, construct="parameter limit"} }
			for previous in 0..<c.function_count { if node_text(&c.parser, c.functions[previous].name_node) == node_text(&c.parser, name) { return Compile_Result{status=.Invalid_Program, offset=c.parser.nodes[name].start, construct="duplicate function"} } }
			c.functions[c.function_count] = Function_IR{name_node=name, params_node=params, body_node=body, arity=arity}
			c.function_count += 1
		} else if kind == "import" {
			if child_count(&c.parser, child) != 6 || c.import_count >= MAX_IMPORTS { return Compile_Result{status=.Invalid_Program, offset=c.parser.nodes[child].start, construct="import"} }
			name := nth_child(&c.parser, child, 1); id_node := nth_child(&c.parser, child, 2); in_node := nth_child(&c.parser, child, 3); out_node := nth_child(&c.parser, child, 4); class_node := nth_child(&c.parser, child, 5)
			id64, id_ok := strconv.parse_u64(node_text(&c.parser, id_node)); inputs64, in_ok := strconv.parse_i64(node_text(&c.parser, in_node)); outputs64, out_ok := strconv.parse_i64(node_text(&c.parser, out_node))
			if !id_ok || id64 > 0xffffff || !in_ok || !out_ok || inputs64 < 0 || outputs64 < 0 || inputs64 > MAX_PARAMS || outputs64 > 1 { return Compile_Result{status=.Invalid_Program, offset=c.parser.nodes[child].start, construct="import fields"} }
			flags := u32(0); classification := node_text(&c.parser, class_node); if classification == "deterministic" { flags=1 } else if classification != "effectful" { return Compile_Result{status=.Invalid_Program, offset=c.parser.nodes[class_node].start, construct="import classification"} }
			for previous in 0..<c.import_count { if c.imports[previous].primitive_id == u32(id64) || node_text(&c.parser, c.imports[previous].name_node) == node_text(&c.parser, name) { return Compile_Result{status=.Invalid_Program, offset=c.parser.nodes[name].start, construct="duplicate import"} } }
			c.imports[c.import_count] = Import_IR{name_node=name, primitive_id=u32(id64), inputs=int(inputs64), outputs=int(outputs64), flags=flags}; c.import_count += 1
		} else if kind != "entry" { return Compile_Result{status=.Unsupported_Construct, offset=c.parser.nodes[child].start, construct=kind} }
		child = c.parser.nodes[child].next
	}
	if c.function_count == 0 { return Compile_Result{status=.Invalid_Program, construct="no functions"} }
	for fi in 0..<c.function_count {
		c.current_function = fi; f := &c.functions[fi]; f.address = c.output.code_count
		heap_before := c.output.heap_words
		f.locals = count_lets(c, f.body_node); c.stack_depth = f.arity+f.locals; c.max_stack = c.stack_depth
		enter_operand := i32(f.arity | f.locals<<12); if _, ok := emit(c, .Enter, enter_operand); !ok { return c.result }
		c.local_count = 0; c.next_local = f.arity
		param := nth_child(&c.parser, f.params_node, 0); slot := 0
		for param >= 0 { c.local_names[c.local_count] = param; c.local_slots[c.local_count] = slot; c.local_count += 1; slot += 1; param = c.parser.nodes[param].next }
		if !compile_expr(c, f.body_node, true) { return c.result }
		if _, ok := emit(c, .Return, effect=-1); !ok { return c.result }
		f.max_stack = c.max_stack
		f.heap_words = c.output.heap_words-heap_before
	}
	for fixup in c.output.fixups[:c.output.fixup_count] {
		if c.functions[fixup.function_index].heap_words != 0 {
			return Compile_Result{status=.Unsupported_Construct, function_name=node_text(&c.parser,c.functions[fixup.function_index].name_node), construct="repeated heap allocation through a call"}
		}
	}
	for fixup in c.output.fixups[:c.output.fixup_count] {
		old := c.output.code[fixup.code_index]; op := Opcode(u8(old>>24))
		c.output.code[fixup.code_index] = encode(op, i32(c.functions[fixup.function_index].address))
	}
	for fi in 0..<c.function_count {
		f := c.functions[fi]; at := fi*FUNCTION_WORDS
		c.output.function_words[at] = name_hash(node_text(&c.parser, f.name_node)); c.output.function_words[at+1] = u32(f.address)
		c.output.function_words[at+2] = u32(f.arity); c.output.function_words[at+3] = u32(f.arity); c.output.function_words[at+4] = 1
		c.output.function_words[at+5] = u32(f.max_stack); c.output.function_words[at+6] = u32(c.function_count*3)
	}
	c.output.function_count = c.function_count
	for ii in 0..<c.import_count {
		imp := c.imports[ii]; at := ii*IMPORT_WORDS
		c.output.import_words[at] = imp.primitive_id; c.output.import_words[at+1] = name_hash(node_text(&c.parser, imp.name_node))
		c.output.import_words[at+2] = u32(imp.inputs); c.output.import_words[at+3] = u32(imp.outputs); c.output.import_words[at+4] = imp.flags
	}
	c.output.import_count = c.import_count
	child = nth_child(&c.parser, root, 1)
	for child >= 0 {
		if node_text(&c.parser, nth_child(&c.parser, child, 0)) == "entry" {
			name := nth_child(&c.parser, child, 1); fi := find_function(c, name)
			if child_count(&c.parser, child) != 2 || fi < 0 || c.functions[fi].arity != 0 { return Compile_Result{status=.Invalid_Program, offset=c.parser.nodes[child].start, construct="zero-arity entry"} }
			at := c.output.entry_count*ENTRY_WORDS; c.output.entry_words[at] = name_hash(node_text(&c.parser, name)); c.output.entry_words[at+1] = u32(fi); c.output.entry_count += 1
		}
		child = c.parser.nodes[child].next
	}
	if c.output.entry_count == 0 { c.output.entry_words[0] = name_hash(node_text(&c.parser, c.functions[c.function_count-1].name_node)); c.output.entry_words[1] = u32(c.function_count-1); c.output.entry_count = 1 }
	// Conservative whole-program bound: every instruction that can grow the
	// stack is covered, independent of branch selection. Call cycles are tail-only.
	heap_profile := Heap_Profile.None; heap_capacity := u32(0)
	if c.output.heap_words > 0 { heap_profile = .Arena; heap_capacity = c.output.heap_words+1 }
	c.output.resources = {u32(c.output.code_count+c.function_count*MAX_LOCALS+1), u32(c.function_count*3+3), heap_capacity, u32(heap_profile), 100000}
	output^ = c.output
	return Compile_Result{status=.Ok}
}

compiled_image_spec :: proc(output: ^Compile_Output) -> Image_Spec {
	features := u32(0)
	for instruction in output.code[:output.code_count] { if Opcode(u8(instruction>>24)) == .Dup_Mul { features |= FEATURE_SUPER } }
	if output.resources[2] != 0 { features |= FEATURE_HEAP }
	if output.import_count != 0 { features |= FEATURE_DEVICE }
	return Image_Spec{
		code=output.code[:output.code_count], constants=output.constants[:output.constant_count],
		functions=output.function_words[:output.function_count*FUNCTION_WORDS],
		entries=output.entry_words[:output.entry_count*ENTRY_WORDS], imports=output.import_words[:output.import_count*IMPORT_WORDS], resources=output.resources, feature_mask=features,
	}
}
