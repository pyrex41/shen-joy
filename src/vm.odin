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
}

Status :: enum u8 {
	Ok,
	Bad_Image,
	Stack_Limit,
	Return_Limit,
	Type_Error,
	Arithmetic_Overflow,
}

Result :: struct {
	status: Status,
	value:  Value,
	pc:     int,
}

Machine :: struct {
	data:    []Value,
	returns: []int,
	sp:      int,
	rp:      int,
	pc:      int,
}

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
	if m.rp < 0 || m.rp >= len(m.returns) { return false }
	m.returns[m.rp] = address
	m.rp += 1
	return true
}

run :: proc(code: []Instruction, m: ^Machine, entry: int = 0) -> Result {
	if m == nil || entry < 0 || entry >= len(code) { return Result{status=.Bad_Image} }
	m.sp, m.rp, m.pc = 0, 0, entry
	for {
		if m.pc < 0 || m.pc >= len(code) { return Result{status=.Bad_Image, pc=m.pc} }
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
		case .Add, .Sub, .Mul, .Eq, .Lt:
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
			case .Eq: if a == b { value = TRUE_VALUE } else { value = FALSE_VALUE }
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
			next = operand_unsigned(ins)
		case .Tail_Call:
			next = operand_unsigned(ins)
		case .Return:
			if m.rp <= 0 { return Result{status=.Bad_Image, pc=m.pc} }
			m.rp -= 1
			next = m.returns[m.rp]
		case .Quote:
			value, ok := to_quote(operand_unsigned(ins))
			if !ok || !push(m, value) { return Result{status=.Stack_Limit, pc=m.pc} }
		case .I:
			value, popped := pop_value(m); if !popped { return Result{status=.Bad_Image, pc=m.pc} }
			address, quoted := from_quote(value); if !quoted { return Result{status=.Type_Error, pc=m.pc} }
			if !push_return(m, next) { return Result{status=.Return_Limit, pc=m.pc} }
			next = address
		case:
			return Result{status=.Bad_Image, pc=m.pc}
		}
		m.pc = next
	}
}
