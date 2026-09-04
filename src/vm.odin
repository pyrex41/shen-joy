package main

Instruction :: u32
Value       :: u32

Opcode :: enum u8 {
	Halt       = 0,
	Push       = 1,
	Dup        = 2,
	Drop       = 3,
	Swap       = 4,
	Add        = 5,
	Sub        = 6,
	Mul        = 7,
	Eq         = 8,
	Lt         = 9,
	Jump       = 10,
	Jump_False = 11,
	Call       = 12,
	Tail_Call  = 13,
	Return     = 14,
	Quote      = 15,
	I          = 16,
	Enter      = 17,
	Load_Local = 18,
	Invoke     = 19,
	Push_True  = 20,
	Push_False = 21,
	Nil        = 22,
	Cons       = 23,
	Head       = 24,
	Tail       = 25,
	Is_Nil     = 26,
	Vector_New = 27,
	Vector_Get = 28,
	Vector_Set = 29,
	Push_Const = 30,
	Store_Local = 31,
	Dup_Mul    = 32,
}

Status :: enum u8 {
	Ok,
	Bad_Image,
	Stack_Limit,
	Return_Limit,
	Type_Error,
	Arithmetic_Overflow,
	Fuel_Exhausted,
	Heap_Limit,
	Missing_Import,
	Unsupported,
	Heap_Bounds,
	Device_Error,
}

Result :: struct {
	status: Status,
	value:  Value,
	pc:     int,
	steps:  u64,
}

Machine :: struct {
	data:    []Value,
	returns: []int, // three words per continuation: pc, saved fp, cleanup flag
	heap:    []Value,
	constants: []Value,
	sp:      int,
	rp:      int,
	hp:      int,
	fp:      int,
	pc:      int,
	fuel:    u64, // zero means unlimited
	steps:   u64,
	entering: bool,
	tailing:  bool,
	device:   Device_Callback,
	device_context: rawptr,
}

Device_Callback :: proc "odin" (primitive_id: u32, machine: ^Machine, ctx: rawptr) -> Status

OPERAND_MASK :: u32(0x00ff_ffff)
FIXNUM_TAG   :: u32(1)
BOOL_TAG     :: u32(2)
QUOTE_TAG    :: u32(3)
TAG_MASK     :: u32(3)
FALSE_VALUE :: Value(BOOL_TAG)
TRUE_VALUE  :: Value((1 << 2) | BOOL_TAG)
FIXNUM_MIN  :: i64(-(1 << 29))
FIXNUM_MAX  :: i64((1 << 29) - 1)

encode :: proc(op: Opcode, operand: i32 = 0) -> Instruction {
	return (u32(op) << 24) | (u32(operand) & OPERAND_MASK)
}

operand_signed :: proc(ins: Instruction) -> i32 {
	x := i32(ins & OPERAND_MASK)
	if (x & 0x0080_0000) != 0 { x -= 0x0100_0000 }
	return x
}

operand_unsigned :: proc(ins: Instruction) -> int {
	return int(ins & OPERAND_MASK)
}

to_fixnum :: proc(x: i64) -> (Value, bool) {
	if x < FIXNUM_MIN || x > FIXNUM_MAX { return 0, false }
	return Value(u32(i32(x)) << 2 | FIXNUM_TAG), true
}

from_fixnum :: proc(x: Value) -> (i32, bool) {
	if (x & TAG_MASK) != FIXNUM_TAG { return 0, false }
	return i32(x) >> 2, true
}

to_quote :: proc(address: int) -> (Value, bool) {
	if address < 0 || address > int(0x3fff_ffff) { return 0, false }
	return Value(u32(address) << 2 | QUOTE_TAG), true
}

from_quote :: proc(value: Value) -> (int, bool) {
	if (value & TAG_MASK) != QUOTE_TAG { return 0, false }
	return int(value >> 2), true
}

push :: proc(m: ^Machine, value: Value) -> bool {
	if m.sp < 0 || m.sp >= len(m.data) { return false }
	m.data[m.sp] = value
	m.sp += 1
	return true
}

pop_value :: proc(m: ^Machine) -> (Value, bool) {
	if m.sp <= 0 || m.sp > len(m.data) { return 0, false }
	m.sp -= 1
	return m.data[m.sp], true
}

push_return :: proc(m: ^Machine, address: int) -> bool {
	if m.rp < 0 || m.rp+3 > len(m.returns) { return false }
	m.returns[m.rp] = address
	m.returns[m.rp+1] = m.fp
	m.returns[m.rp+2] = 0
	m.rp += 3
	return true
}

heap_allocate :: proc(m: ^Machine, words: int) -> (int, bool) {
	if words <= 0 || m.hp < 1 || m.hp+words > len(m.heap) { return 0, false }
	at := m.hp
	m.hp += words
	return at, true
}

heap_index :: proc(value: Value) -> (int, bool) {
	if value == 0 || (value&TAG_MASK) != 0 { return 0, false }
	return int(value>>2), true
}

run :: proc(code: []Instruction, m: ^Machine, entry: int = 0) -> Result {
	if m == nil || entry < 0 || entry >= len(code) { return Result{status=.Bad_Image} }
	m.sp, m.rp, m.pc, m.fp = 0, 0, entry, 0
	m.hp = 1
	m.entering, m.tailing = false, false
	m.steps = 0
	for {
		if m.fuel != 0 && m.steps >= m.fuel { return Result{status=.Fuel_Exhausted, pc=m.pc} }
		if m.pc < 0 || m.pc >= len(code) { return Result{status=.Bad_Image, pc=m.pc} }
		m.steps += 1
		ins := code[m.pc]
		op := Opcode(u8(ins >> 24))
		next := m.pc + 1
		#partial switch op {
		case .Halt:
			value: Value
			if m.sp > 0 { value = m.data[m.sp-1] }
			return Result{status=.Ok, value=value, pc=m.pc}
		case .Push:
			value, ok := to_fixnum(i64(operand_signed(ins)))
			if !ok { return Result{status=.Arithmetic_Overflow, pc=m.pc} }
			if !push(m, value) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Dup:
			if m.sp <= 0 || !push(m, m.data[m.sp-1]) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Drop:
			_, ok := pop_value(m); if !ok { return Result{status=.Bad_Image, pc=m.pc} }
		case .Swap:
			if m.sp < 2 { return Result{status=.Bad_Image, pc=m.pc} }
			m.data[m.sp-1], m.data[m.sp-2] = m.data[m.sp-2], m.data[m.sp-1]
		case .Eq:
			raw_b, bok := pop_value(m); raw_a, aok := pop_value(m)
			if !bok || !aok { return Result{status=.Bad_Image, pc=m.pc} }
			if (raw_a&TAG_MASK)==0 || (raw_b&TAG_MASK)==0 { return Result{status=.Unsupported, pc=m.pc} }
			value := FALSE_VALUE; if raw_a == raw_b { value = TRUE_VALUE }
			if !push(m, value) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Add, .Sub, .Mul, .Lt:
			raw_b, bok := pop_value(m); raw_a, aok := pop_value(m)
			if !bok || !aok { return Result{status=.Bad_Image, pc=m.pc} }
			a, at := from_fixnum(raw_a); b, bt := from_fixnum(raw_b)
			if !at || !bt { return Result{status=.Type_Error, pc=m.pc} }
			value: Value
			ok := true
			#partial switch op {
			case .Add: value, ok = to_fixnum(i64(a)+i64(b))
			case .Sub: value, ok = to_fixnum(i64(a)-i64(b))
			case .Mul: value, ok = to_fixnum(i64(a)*i64(b))
			case .Lt: if a < b { value = TRUE_VALUE } else { value = FALSE_VALUE }
			}
			if !ok { return Result{status=.Arithmetic_Overflow, pc=m.pc} }
			if !push(m, value) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Jump:
			next += int(operand_signed(ins))
		case .Jump_False:
			condition, ok := pop_value(m); if !ok { return Result{status=.Bad_Image, pc=m.pc} }
			if condition == FALSE_VALUE { next += int(operand_signed(ins)) } else if condition != TRUE_VALUE { return Result{status=.Type_Error, pc=m.pc} }
		case .Call:
			if !push_return(m, next) { return Result{status=.Return_Limit, pc=m.pc} }
			m.entering = true
			next = operand_unsigned(ins)
		case .Tail_Call:
			m.tailing = true
			next = operand_unsigned(ins)
		case .Return:
			if m.rp < 3 {
				value: Value; if m.sp > 0 { value = m.data[m.sp-1] }
				return Result{status=.Ok, value=value, pc=m.pc}
			}
			address, saved_fp, cleanup := m.returns[m.rp-3], m.returns[m.rp-2], m.returns[m.rp-1]
			m.rp -= 3
			if cleanup != 0 {
				value, ok := pop_value(m); if !ok { return Result{status=.Bad_Image, pc=m.pc} }
				m.sp = m.fp
				if !push(m, value) { return Result{status=.Stack_Limit, pc=m.pc} }
			}
			m.fp = saved_fp
			next = address
		case .Quote:
			value, ok := to_quote(operand_unsigned(ins))
			if !ok || !push(m, value) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .I:
			value, popped := pop_value(m); if !popped { return Result{status=.Bad_Image, pc=m.pc} }
			address, quoted := from_quote(value); if !quoted { return Result{status=.Type_Error, pc=m.pc} }
			if !push_return(m, next) { return Result{status=.Return_Limit, pc=m.pc} }
			next = address
		case .Enter:
			operand := operand_unsigned(ins)
			arity := operand&0xfff
			extra := (operand>>12)&0xfff
			if arity > m.sp { return Result{status=.Bad_Image, pc=m.pc} }
			if m.tailing {
				source := m.sp-arity
				for i in 0..<arity { m.data[m.fp+i] = m.data[source+i] }
				m.sp = m.fp+arity
				m.tailing = false
			} else {
				m.fp = m.sp-arity
				if m.entering {
					if m.rp < 3 { return Result{status=.Bad_Image, pc=m.pc} }
					m.returns[m.rp-1] = 1
				}
			}
			m.entering = false
			for _ in 0..<extra { if !push(m, 0) { return Result{status=.Stack_Limit, pc=m.pc} } }
		case .Load_Local:
			index := operand_unsigned(ins)
			if index < 0 || m.fp+index < 0 || m.fp+index >= m.sp { return Result{status=.Bad_Image, pc=m.pc} }
			if !push(m, m.data[m.fp+index]) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Store_Local:
			index := operand_unsigned(ins)
			value, popped := pop_value(m); if !popped { return Result{status=.Bad_Image, pc=m.pc} }
			if index < 0 || m.fp+index < 0 || m.fp+index >= m.sp { return Result{status=.Bad_Image, pc=m.pc} }
			m.data[m.fp+index] = value
		case .Push_Const:
			index := operand_unsigned(ins)
			if index < 0 || index >= len(m.constants) { return Result{status=.Bad_Image, pc=m.pc} }
			if !push(m, m.constants[index]) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Dup_Mul:
			if m.sp <= 0 { return Result{status=.Bad_Image, pc=m.pc} }
			a, typed := from_fixnum(m.data[m.sp-1]); if !typed { return Result{status=.Type_Error, pc=m.pc} }
			value, ok := to_fixnum(i64(a)*i64(a)); if !ok { return Result{status=.Arithmetic_Overflow, pc=m.pc} }
			m.data[m.sp-1] = value
		case .Invoke:
			if m.device == nil { return Result{status=.Missing_Import, pc=m.pc} }
			if status := m.device(u32(operand_unsigned(ins)), m, m.device_context); status != .Ok { return Result{status=status, pc=m.pc} }
		case .Push_True:
			if !push(m, TRUE_VALUE) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Push_False:
			if !push(m, FALSE_VALUE) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Nil:
			if !push(m, 0) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Cons:
			tail, tok := pop_value(m); head, hok := pop_value(m)
			if !tok || !hok { return Result{status=.Bad_Image, pc=m.pc} }
			at, allocated := heap_allocate(m, 3); if !allocated { return Result{status=.Heap_Limit, pc=m.pc} }
			m.heap[at], m.heap[at+1], m.heap[at+2] = 1, head, tail
			if !push(m, Value(u32(at)<<2)) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Head, .Tail:
			ref, popped := pop_value(m); if !popped { return Result{status=.Bad_Image, pc=m.pc} }
			at, referenced := heap_index(ref)
			if !referenced || at+2 >= m.hp || at+2 >= len(m.heap) || m.heap[at] != 1 { return Result{status=.Heap_Bounds, pc=m.pc} }
			offset := 1; if op == .Tail { offset = 2 }
			if !push(m, m.heap[at+offset]) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Is_Nil:
			value, popped := pop_value(m); if !popped { return Result{status=.Bad_Image, pc=m.pc} }
			result := FALSE_VALUE; if value == 0 { result = TRUE_VALUE }
			if !push(m, result) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Vector_New:
			length := operand_unsigned(ins)
			at, allocated := heap_allocate(m, 1+length); if !allocated { return Result{status=.Heap_Limit, pc=m.pc} }
			m.heap[at] = Value(u32(length)<<8|2)
			for i in 0..<length { m.heap[at+1+i] = 0 }
			if !push(m, Value(u32(at)<<2)) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Vector_Get:
			index_raw, iok := pop_value(m); ref, rok := pop_value(m); if !iok || !rok { return Result{status=.Bad_Image, pc=m.pc} }
			index, fix := from_fixnum(index_raw); at, referenced := heap_index(ref)
			if !fix || !referenced || at >= m.hp || at >= len(m.heap) || (m.heap[at]&0xff) != 2 { return Result{status=.Type_Error, pc=m.pc} }
			length := int(m.heap[at]>>8); if index < 0 || int(index) >= length || at+1+int(index) >= m.hp { return Result{status=.Heap_Bounds, pc=m.pc} }
			if !push(m, m.heap[at+1+int(index)]) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .Vector_Set:
			value, vok := pop_value(m); index_raw, iok := pop_value(m); ref, rok := pop_value(m)
			if !vok || !iok || !rok { return Result{status=.Bad_Image, pc=m.pc} }
			index, fix := from_fixnum(index_raw); at, referenced := heap_index(ref)
			if !fix || !referenced || at >= m.hp || at >= len(m.heap) || (m.heap[at]&0xff) != 2 { return Result{status=.Type_Error, pc=m.pc} }
			length := int(m.heap[at]>>8); if index < 0 || int(index) >= length || at+1+int(index) >= m.hp { return Result{status=.Heap_Bounds, pc=m.pc} }
			m.heap[at+1+int(index)] = value
			if !push(m, ref) { return Result{status=.Stack_Limit, pc=m.pc} }
		case:
			return Result{status=.Bad_Image, pc=m.pc}
		}
		m.pc = next
	}
}
