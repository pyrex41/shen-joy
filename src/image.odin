package main

// Version 1 image support is deliberately independent of files and the OS.
// The decoder and validator borrow caller-owned bytes and allocate no memory.

IMAGE_MAGIC        :: u32(0x31594a53) // "SJY1" in little endian
IMAGE_VERSION      :: u16(1)
IMAGE_ENDIAN_MARK  :: u32(0x0102_0304)
IMAGE_HEADER_SIZE  :: 32
SECTION_ENTRY_SIZE :: 16
IMAGE_SECTION_COUNT :: 7
FEATURE_HEAP         :: u32(1<<0)
FEATURE_DEVICE       :: u32(1<<1)
FEATURE_DEBUG        :: u32(1<<2)
FEATURE_SUPER        :: u32(1<<3)
KNOWN_FEATURES       :: FEATURE_HEAP|FEATURE_DEVICE|FEATURE_DEBUG|FEATURE_SUPER

Section_Kind :: enum u32 {
	Code      = 1,
	Constants = 2,
	Functions = 3,
	Entries   = 4,
	Imports   = 5,
	Resources = 6,
	Debug     = 7,
}

Heap_Profile :: enum u32 {
	None,
	Arena,
	Region,
	Copying,
	Hosted,
}

SECTION_CODE      :: 0
SECTION_CONSTANTS :: 1
SECTION_FUNCTIONS :: 2
SECTION_ENTRIES   :: 3
SECTION_IMPORTS   :: 4
SECTION_RESOURCES :: 5
SECTION_DEBUG     :: 6

FUNCTION_WORDS :: 7 // name id, address, arity, inputs, outputs, max data, max return
ENTRY_WORDS    :: 2 // name id, function index
IMPORT_WORDS   :: 5 // primitive id, name id, inputs, outputs, flags
RESOURCE_WORDS :: 5 // data, return, heap words, heap profile, default fuel

Section_View :: struct {
	kind:   Section_Kind,
	offset: u32,
	size:   u32,
	count:  u32,
}

Image_View :: struct {
	bytes:        []u8,
	feature_mask: u32,
	sections:     [IMAGE_SECTION_COUNT]Section_View,
}

Image_Spec :: struct {
	code:          []Instruction,
	constants:     []Value,
	functions:     []u32,
	entries:       []u32,
	imports:       []u32,
	resources:     [RESOURCE_WORDS]u32,
	debug:         []u8,
	feature_mask:  u32,
}

Target_Config :: struct {
	feature_mask: u32,
	data_words: u32,
	return_words: u32,
	heap_words: u32,
	primitive_ids: []u32,
}

image_size :: proc(spec: ^Image_Spec) -> (int, bool) {
	if spec == nil || len(spec.functions)%FUNCTION_WORDS != 0 ||
	   len(spec.entries)%ENTRY_WORDS != 0 || len(spec.imports)%IMPORT_WORDS != 0 {
		return 0, false
	}
	size64 := u64(IMAGE_HEADER_SIZE + IMAGE_SECTION_COUNT*SECTION_ENTRY_SIZE) +
	          u64(len(spec.code))*4 + u64(len(spec.constants))*4 +
	          u64(len(spec.functions))*4 + u64(len(spec.entries))*4 +
	          u64(len(spec.imports))*4 + RESOURCE_WORDS*4 + u64(len(spec.debug))
	// Every section starts at a four-byte boundary.
	size64 = (size64 + 3) & ~u64(3)
	if size64 > u64(max(int)) || size64 > u64(max(u32)) { return 0, false }
	return int(size64), true
}

put_u16 :: proc(dst: []u8, at: int, x: u16) -> bool {
	if at < 0 || at+2 > len(dst) { return false }
	dst[at] = u8(x); dst[at+1] = u8(x >> 8)
	return true
}

put_u32 :: proc(dst: []u8, at: int, x: u32) -> bool {
	if at < 0 || at+4 > len(dst) { return false }
	dst[at] = u8(x); dst[at+1] = u8(x >> 8); dst[at+2] = u8(x >> 16); dst[at+3] = u8(x >> 24)
	return true
}

get_u16 :: proc(src: []u8, at: int) -> (u16, bool) {
	if at < 0 || at+2 > len(src) { return 0, false }
	return u16(src[at]) | u16(src[at+1])<<8, true
}

get_u32 :: proc(src: []u8, at: int) -> (u32, bool) {
	if at < 0 || at+4 > len(src) { return 0, false }
	return u32(src[at]) | u32(src[at+1])<<8 | u32(src[at+2])<<16 | u32(src[at+3])<<24, true
}

image_checksum :: proc(bytes: []u8) -> u32 {
	// FNV-1a over the complete image, treating the checksum field as zero.
	h := u32(2166136261)
	for source_b, i in bytes {
		b := source_b
		if i >= 20 && i < 24 { b = 0 }
		h = (h ~ u32(b))*u32(16777619)
	}
	return h
}

write_words :: proc(dst: []u8, at: int, words: []u32) -> (int, bool) {
	cursor := at
	for word in words {
		if !put_u32(dst, cursor, word) { return cursor, false }
		cursor += 4
	}
	return cursor, true
}

encode_image :: proc(spec: ^Image_Spec, dst: []u8) -> (int, Status) {
	total, valid := image_size(spec)
	if !valid || len(dst) < total { return 0, .Bad_Image }
	for i in 0..<total { dst[i] = 0 }
	put_u32(dst, 0, IMAGE_MAGIC)
	put_u16(dst, 4, IMAGE_VERSION)
	put_u16(dst, 6, IMAGE_HEADER_SIZE)
	put_u32(dst, 8, u32(total))
	put_u32(dst, 12, IMAGE_SECTION_COUNT)
	put_u32(dst, 16, spec.feature_mask)
	put_u32(dst, 24, IMAGE_ENDIAN_MARK)

	at := IMAGE_HEADER_SIZE + IMAGE_SECTION_COUNT*SECTION_ENTRY_SIZE
	kinds := [IMAGE_SECTION_COUNT]Section_Kind{.Code, .Constants, .Functions, .Entries, .Imports, .Resources, .Debug}
	sizes := [IMAGE_SECTION_COUNT]int{
		len(spec.code)*4, len(spec.constants)*4, len(spec.functions)*4,
		len(spec.entries)*4, len(spec.imports)*4, RESOURCE_WORDS*4, len(spec.debug),
	}
	counts := [IMAGE_SECTION_COUNT]int{
		len(spec.code), len(spec.constants), len(spec.functions)/FUNCTION_WORDS,
		len(spec.entries)/ENTRY_WORDS, len(spec.imports)/IMPORT_WORDS, 1, len(spec.debug),
	}
	for i in 0..<IMAGE_SECTION_COUNT {
		at = (at+3)&~3
		entry := IMAGE_HEADER_SIZE+i*SECTION_ENTRY_SIZE
		put_u32(dst, entry, u32(kinds[i])); put_u32(dst, entry+4, u32(at))
		put_u32(dst, entry+8, u32(sizes[i])); put_u32(dst, entry+12, u32(counts[i]))
		switch i {
		case SECTION_CODE:
			for x in spec.code { put_u32(dst, at, u32(x)); at += 4 }
		case SECTION_CONSTANTS:
			for x in spec.constants { put_u32(dst, at, u32(x)); at += 4 }
		case SECTION_FUNCTIONS: at, _ = write_words(dst, at, spec.functions)
		case SECTION_ENTRIES: at, _ = write_words(dst, at, spec.entries)
		case SECTION_IMPORTS: at, _ = write_words(dst, at, spec.imports)
		case SECTION_RESOURCES: at, _ = write_words(dst, at, spec.resources[:])
		case SECTION_DEBUG:
			copy(dst[at:at+len(spec.debug)], spec.debug); at += len(spec.debug)
		}
	}
	put_u32(dst, 20, image_checksum(dst[:total]))
	return total, .Ok
}

section_words :: proc(image: ^Image_View, index: int) -> []u8 {
	s := image.sections[index]
	return image.bytes[int(s.offset):int(s.offset+s.size)]
}

word_at :: proc(section: []u8, index: int) -> (u32, bool) {
	return get_u32(section, index*4)
}

image_resource :: proc(image: ^Image_View, index: int) -> u32 {
	value, _ := word_at(section_words(image, SECTION_RESOURCES), index)
	return value
}

decode_code_words :: proc(image: ^Image_View, dst: []Instruction) -> Status {
	if image == nil || len(dst) < int(image.sections[SECTION_CODE].count) { return .Bad_Image }
	code := section_words(image, SECTION_CODE)
	for i in 0..<int(image.sections[SECTION_CODE].count) {
		word, ok := word_at(code, i); if !ok { return .Bad_Image }
		dst[i] = Instruction(word)
	}
	return .Ok
}

image_entry_address :: proc(image: ^Image_View, name_id: u32 = 0) -> (int, bool) {
	entries := section_words(image, SECTION_ENTRIES)
	functions := section_words(image, SECTION_FUNCTIONS)
	for i in 0..<int(image.sections[SECTION_ENTRIES].count) {
		candidate, _ := word_at(entries, i*ENTRY_WORDS)
		function_id, _ := word_at(entries, i*ENTRY_WORDS+1)
		if name_id == 0 || candidate == name_id {
			address, ok := word_at(functions, int(function_id)*FUNCTION_WORDS+1)
			return int(address), ok
		}
	}
	return 0, false
}

validate_code :: proc(code: []u8, constants: []u8, functions: []u8, imports: []u8, resources: []u8) -> Status {
	word_count := len(code)/4
	constant_count := len(constants)/4
	function_count := len(functions)/(FUNCTION_WORDS*4)
	import_count := len(imports)/(IMPORT_WORDS*4)
	for i in 0..<word_count {
		ins, ok := word_at(code, i); if !ok { return .Bad_Image }
		op_raw := u8(ins >> 24)
		if op_raw > u8(Opcode.Dup_Mul) { return .Bad_Image }
		op := Opcode(op_raw)
		operand := operand_unsigned(Instruction(ins))
		#partial switch op {
		case .Jump, .Jump_False:
			target := i+1+int(operand_signed(Instruction(ins)))
			if target < 0 || target >= word_count { return .Bad_Image }
		case .Call, .Tail_Call:
			target := operand_unsigned(Instruction(ins))
			found := false
			for f in 0..<function_count {
				address, _ := word_at(functions, f*FUNCTION_WORDS+1)
				if int(address) == target { found = true; break }
			}
			if !found { return .Bad_Image }
		case .Quote:
			if operand >= word_count { return .Bad_Image }
		case .Push_Const:
			if operand >= constant_count { return .Bad_Image }
		case .Enter:
			found := false
			for f in 0..<function_count {
				address, _ := word_at(functions, f*FUNCTION_WORDS+1); arity, _ := word_at(functions, f*FUNCTION_WORDS+2)
				if int(address) == i { found = true; if u32(operand&0xfff) != arity { return .Bad_Image }; break }
			}
			if !found { return .Bad_Image }
		case .Vector_New:
			heap_words, _ := word_at(resources, 2)
			if u64(operand)+2 > u64(heap_words) { return .Bad_Image }
		case .Invoke:
			found := false
			for import_index in 0..<import_count {
				primitive_id, _ := word_at(imports, import_index*IMPORT_WORDS)
				if int(primitive_id) == operand_unsigned(Instruction(ins)) { found = true; break }
			}
			if !found { return .Bad_Image }
		case .Halt, .Dup, .Drop, .Swap, .Add, .Sub, .Mul, .Eq, .Lt, .Return, .I,
		     .Push_True, .Push_False, .Nil, .Cons, .Head, .Tail, .Is_Nil,
		     .Vector_Get, .Vector_Set, .Dup_Mul:
			if operand != 0 { return .Bad_Image }
		case:
		}
	}
	return .Ok
}

validate_target :: proc(image: ^Image_View, target: ^Target_Config) -> Status {
	if image == nil || target == nil || image.feature_mask&~target.feature_mask != 0 { return .Unsupported }
	if image_resource(image, 0) > target.data_words { return .Stack_Limit }
	if image_resource(image, 1) > target.return_words { return .Return_Limit }
	if image_resource(image, 2) > target.heap_words { return .Heap_Limit }
	imports := section_words(image, SECTION_IMPORTS)
	for i in 0..<int(image.sections[SECTION_IMPORTS].count) {
		required, _ := word_at(imports, i*IMPORT_WORDS); found := false
		for supplied in target.primitive_ids { if supplied == required { found = true; break } }
		if !found { return .Missing_Import }
	}
	return .Ok
}

decode_and_validate_image :: proc(bytes: []u8) -> (Image_View, Status) {
	view := Image_View{bytes=bytes}
	if len(bytes) < IMAGE_HEADER_SIZE+IMAGE_SECTION_COUNT*SECTION_ENTRY_SIZE { return view, .Bad_Image }
	magic, m := get_u32(bytes, 0); version, v := get_u16(bytes, 4); header, h := get_u16(bytes, 6)
	total, t := get_u32(bytes, 8); section_count, s := get_u32(bytes, 12)
	feature, f := get_u32(bytes, 16); checksum, c := get_u32(bytes, 20); endian, e := get_u32(bytes, 24)
	reserved, r := get_u32(bytes, 28)
	if !m || !v || !h || !t || !s || !f || !c || !e || !r ||
	   magic != IMAGE_MAGIC || version != IMAGE_VERSION || int(header) != IMAGE_HEADER_SIZE ||
	   section_count != IMAGE_SECTION_COUNT || u64(total) != u64(len(bytes)) ||
	   endian != IMAGE_ENDIAN_MARK || reserved != 0 || checksum != image_checksum(bytes) || (feature&~KNOWN_FEATURES) != 0 {
		return view, .Bad_Image
	}
	view.feature_mask = feature
	data_start := u32(IMAGE_HEADER_SIZE+IMAGE_SECTION_COUNT*SECTION_ENTRY_SIZE)
	last_end := data_start
	for i in 0..<IMAGE_SECTION_COUNT {
		at := IMAGE_HEADER_SIZE+i*SECTION_ENTRY_SIZE
		kind, k := get_u32(bytes, at); offset, o := get_u32(bytes, at+4)
		size, z := get_u32(bytes, at+8); count, n := get_u32(bytes, at+12)
		if !k || !o || !z || !n || kind != u32(i+1) || offset%4 != 0 || offset < last_end ||
		   u64(offset)+u64(size) > u64(total) { return view, .Bad_Image }
		view.sections[i] = Section_View{kind=Section_Kind(kind), offset=offset, size=size, count=count}
		last_end = offset+size
	}
	if last_end > total { return view, .Bad_Image }
	code := view.sections[SECTION_CODE]; constants := view.sections[SECTION_CONSTANTS]
	functions := view.sections[SECTION_FUNCTIONS]; entries := view.sections[SECTION_ENTRIES]
	imports := view.sections[SECTION_IMPORTS]; resources := view.sections[SECTION_RESOURCES]
	if code.size != code.count*4 || constants.size != constants.count*4 ||
	   functions.size != functions.count*FUNCTION_WORDS*4 || entries.size != entries.count*ENTRY_WORDS*4 ||
	   imports.size != imports.count*IMPORT_WORDS*4 || resources.size != RESOURCE_WORDS*4 || resources.count != 1 {
		return view, .Bad_Image
	}
	code_bytes := section_words(&view, SECTION_CODE)
	constant_bytes := section_words(&view, SECTION_CONSTANTS)
	function_bytes := section_words(&view, SECTION_FUNCTIONS)
	entry_bytes := section_words(&view, SECTION_ENTRIES)
	import_bytes := section_words(&view, SECTION_IMPORTS)
	resource_bytes := section_words(&view, SECTION_RESOURCES)
	heap_words, _ := word_at(resource_bytes, 2); heap_profile, _ := word_at(resource_bytes, 3)
	if heap_profile > u32(Heap_Profile.Arena) || (heap_profile == 0) != (heap_words == 0) ||
	   ((feature&FEATURE_HEAP)!=0) != (heap_words!=0) || ((feature&FEATURE_DEVICE)!=0) != (imports.count!=0) ||
	   ((feature&FEATURE_DEBUG)!=0) != (view.sections[SECTION_DEBUG].size!=0) { return view, .Bad_Image }
	for i in 0..<int(constants.count) {
		value, _ := word_at(constant_bytes, i); tag := value&TAG_MASK
		if tag == BOOL_TAG && value != FALSE_VALUE && value != TRUE_VALUE { return view, .Bad_Image }
		if tag == 0 { return view, .Bad_Image }
		if tag == QUOTE_TAG && value>>2 >= code.count { return view, .Bad_Image }
	}
	for i in 0..<int(functions.count) {
		address, _ := word_at(function_bytes, i*FUNCTION_WORDS+1)
		arity, _ := word_at(function_bytes, i*FUNCTION_WORDS+2)
		inputs, _ := word_at(function_bytes, i*FUNCTION_WORDS+3)
		outputs, _ := word_at(function_bytes, i*FUNCTION_WORDS+4)
		max_data, _ := word_at(function_bytes, i*FUNCTION_WORDS+5); max_return, _ := word_at(function_bytes, i*FUNCTION_WORDS+6)
		if address >= code.count || arity != inputs || outputs > 1 || max_data > image_resource(&view, 0) || max_return > image_resource(&view, 1) { return view, .Bad_Image }
		if i > 0 { previous, _ := word_at(function_bytes, (i-1)*FUNCTION_WORDS+1); if address <= previous { return view, .Bad_Image } }
	}
	for i in 0..<int(entries.count) {
		function_id, _ := word_at(entry_bytes, i*ENTRY_WORDS+1)
		if function_id >= functions.count { return view, .Bad_Image }
	}
	for i in 0..<int(imports.count) {
		primitive_id, _ := word_at(import_bytes, i*IMPORT_WORDS)
		flags, _ := word_at(import_bytes, i*IMPORT_WORDS+4); if flags&~u32(1) != 0 { return view, .Bad_Image }
		for j in 0..<i {
			other, _ := word_at(import_bytes, j*IMPORT_WORDS)
			if primitive_id == other { return view, .Bad_Image }
		}
	}
	if status := validate_code(code_bytes, constant_bytes, function_bytes, import_bytes, resource_bytes); status != .Ok { return view, status }
	for i in 0..<int(code.count) {
		instruction, _ := word_at(code_bytes, i); op := Opcode(u8(instruction>>24))
		if op == .Dup_Mul && feature&FEATURE_SUPER == 0 { return view, .Bad_Image }
		if op >= .Nil && op <= .Vector_Set && feature&FEATURE_HEAP == 0 { return view, .Bad_Image }
		if op == .Invoke && feature&FEATURE_DEVICE == 0 { return view, .Bad_Image }
	}
	return view, .Ok
}
