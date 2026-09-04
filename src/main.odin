package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:time"

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

hex_nibble :: proc(b: u8) -> (u32, bool) {
	if b >= '0' && b <= '9' { return u32(b-'0'), true }
	if b >= 'a' && b <= 'f' { return u32(b-'a'+10), true }
	if b >= 'A' && b <= 'F' { return u32(b-'A'+10), true }
	return 0, false
}

run_hex_file :: proc(path: string) -> (Result, bool) {
	bytes, err := os.read_entire_file(path, context.allocator); if err != nil { return Result{}, false }
	defer delete(bytes)
	code := make([]Instruction, len(bytes)/2+1); defer delete(code)
	count, at := 0, 0
	for at < len(bytes) {
		for at < len(bytes) && (bytes[at]==' ' || bytes[at]=='\t' || bytes[at]=='\r' || bytes[at]=='\n') { at += 1 }
		if at >= len(bytes) { break }
		word, digits := u32(0), 0
		for at < len(bytes) && bytes[at]!=' ' && bytes[at]!='\t' && bytes[at]!='\r' && bytes[at]!='\n' {
			nibble, ok := hex_nibble(bytes[at]); if !ok || digits >= 8 { return Result{}, false }
			word = word<<4|nibble; digits += 1; at += 1
		}
		if digits == 0 || count >= len(code) { return Result{}, false }
		code[count] = Instruction(word); count += 1
	}
	data: [64]Value; returns: [24]int; heap: [1]Value
	machine := Machine{data=data[:], returns=returns[:], heap=heap[:], fuel=100}
	result := run(code[:count], &machine); result.steps = machine.steps
	return result, true
}

main :: proc() {
	if len(os.args) == 2 && os.args[1] == "--version" {
		fmt.println("shen-joy image-v1 bounded-s42-subset")
		return
	}
	if len(os.args) >= 2 && os.args[1] == "unsupported" {
		fmt.eprintln("SKIP: shen-joy consumes validated images; source Shen/eval/REPL are host-only")
		os.exit(3)
	}
	if len(os.args) == 2 && os.args[1] == "--demo" {
		value, status := demo()
		if status != .Ok { fmt.println("error: ", status); return }
		n, ok := from_fixnum(value)
		if !ok { fmt.println("error: non-fixnum result"); return }
		fmt.println(n)
		return
	}
	if len(os.args) == 3 && os.args[1] == "run-hex" {
		result, ok := run_hex_file(os.args[2]); if !ok { fmt.eprintln("error: malformed hex vector"); os.exit(2) }
		n, fix := from_fixnum(result.value); if !fix { n = 0 }
		fmt.printf("RESULT=%d STATUS=%d STEPS=%d\n", n, int(result.status), result.steps)
		return
	}
	if len(os.args) >= 3 && os.args[1] == "validate" {
		bytes, err := os.read_entire_file(os.args[2], context.allocator)
		if err != nil { fmt.eprintln("error: cannot read image: ", err); os.exit(2) }
		defer delete(bytes)
		_, status := decode_and_validate_image(bytes)
		if status != .Ok { fmt.eprintln("invalid: ", status); os.exit(1) }
		fmt.println("valid image format v1")
		return
	}
	if len(os.args) >= 3 && os.args[1] == "inspect" {
		bytes, err := os.read_entire_file(os.args[2], context.allocator)
		if err != nil { fmt.eprintln("error: cannot read image: ", err); os.exit(2) }
		defer delete(bytes)
		image, status := decode_and_validate_image(bytes)
		if status != .Ok { fmt.eprintln("invalid: ", status); os.exit(1) }
		fmt.println("format-version: 1")
		fmt.println("feature-mask: ", image.feature_mask)
		fmt.println("functions: ", image.sections[SECTION_FUNCTIONS].count)
		fmt.println("entries: ", image.sections[SECTION_ENTRIES].count)
		fmt.println("imports: ", image.sections[SECTION_IMPORTS].count)
		fmt.println("data-stack: ", image_resource(&image, 0))
		fmt.println("return-stack: ", image_resource(&image, 1))
		fmt.println("heap-words: ", image_resource(&image, 2))
		fmt.println("heap-profile: ", image_resource(&image, 3))
		fmt.println("default-fuel: ", image_resource(&image, 4))
		fmt.println("code-bytes: ", image.sections[SECTION_CODE].size)
		fmt.println("constant-bytes: ", image.sections[SECTION_CONSTANTS].size)
		fmt.println("debug-metadata: ", image.sections[SECTION_DEBUG].size != 0)
		fmt.printf("checksum: %08x\n", image_checksum(bytes))
		function_bytes := section_words(&image,SECTION_FUNCTIONS)
		for i in 0..<int(image.sections[SECTION_FUNCTIONS].count) {
			name,_:=word_at(function_bytes,i*FUNCTION_WORDS); address,_:=word_at(function_bytes,i*FUNCTION_WORDS+1); arity,_:=word_at(function_bytes,i*FUNCTION_WORDS+2)
			max_data,_:=word_at(function_bytes,i*FUNCTION_WORDS+5); max_return,_:=word_at(function_bytes,i*FUNCTION_WORDS+6)
			fmt.printf("function[%d]: name-id=%08x address=%d arity=%d max-data=%d max-return=%d\n",i,name,address,arity,max_data,max_return)
		}
		import_bytes := section_words(&image,SECTION_IMPORTS)
		for i in 0..<int(image.sections[SECTION_IMPORTS].count) {
			id,_:=word_at(import_bytes,i*IMPORT_WORDS); name,_:=word_at(import_bytes,i*IMPORT_WORDS+1); inputs,_:=word_at(import_bytes,i*IMPORT_WORDS+2); outputs,_:=word_at(import_bytes,i*IMPORT_WORDS+3); flags,_:=word_at(import_bytes,i*IMPORT_WORDS+4)
			fmt.printf("import[%d]: id=%d name-id=%08x inputs=%d outputs=%d flags=%d\n",i,id,name,inputs,outputs,flags)
		}
		return
	}
	if len(os.args) >= 3 && os.args[1] == "run" {
		bytes, err := os.read_entire_file(os.args[2], context.allocator)
		if err != nil { fmt.eprintln("error: cannot read image: ", err); os.exit(2) }
		defer delete(bytes)
		image, status := decode_and_validate_image(bytes)
		if status != .Ok { fmt.eprintln("invalid: ", status); os.exit(1) }
		code := make([]Instruction, int(image.sections[SECTION_CODE].count)); defer delete(code)
		if decode_code_words(&image, code) != .Ok { fmt.eprintln("invalid code"); os.exit(1) }
		data_size := int(image_resource(&image, 0)); if data_size < 1 { data_size = 1 }
		return_size := int(image_resource(&image, 1)); if return_size < 1 { return_size = 1 }
		heap_size := int(image_resource(&image, 2)); if heap_size < 1 { heap_size = 1 }
		data := make([]Value, data_size); returns := make([]int, return_size); heap := make([]Value, heap_size)
		constants := make([]Value, int(image.sections[SECTION_CONSTANTS].count))
		defer delete(data); defer delete(returns); defer delete(heap); defer delete(constants)
		constant_bytes := section_words(&image, SECTION_CONSTANTS)
		for value, i in constants { _ = value; word, _ := word_at(constant_bytes, i); constants[i] = Value(word) }
		entry_name_id := u32(0)
		fuel := u64(image_resource(&image, 4))
		for i := 3; i+1 < len(os.args); i += 2 {
			if os.args[i] == "--fuel" {
				parsed, parse_ok := strconv.parse_u64(os.args[i+1]); if !parse_ok { fmt.eprintln("error: bad fuel"); os.exit(2) }
				fuel = parsed
			}
			if os.args[i] == "--entry" { entry_name_id = name_hash(os.args[i+1]) }
		}
		entry, found := image_entry_address(&image, entry_name_id); if !found { fmt.eprintln("error: image has no matching entry"); os.exit(1) }
		target := Target_Config{feature_mask=KNOWN_FEATURES, data_words=u32(data_size), return_words=u32(return_size), heap_words=u32(heap_size)}
		if target_status := validate_target(&image, &target); target_status != .Ok { fmt.eprintln("target rejected image: ", target_status); os.exit(1) }
		machine := Machine{data=data, returns=returns, heap=heap, constants=constants, fuel=fuel}
		result := run(code, &machine, entry)
		if result.status != .Ok { fmt.eprintln("status: ", result.status); os.exit(1) }
		if n, ok := from_fixnum(result.value); ok { fmt.println(n) } else if result.value == TRUE_VALUE { fmt.println("true") } else if result.value == FALSE_VALUE { fmt.println("false") } else { fmt.println(result.value) }
		return
	}
	if len(os.args) >= 3 && os.args[1] == "bench" {
		bytes, err := os.read_entire_file(os.args[2], context.allocator)
		if err != nil { fmt.eprintln("error: cannot read image: ", err); os.exit(2) }
		defer delete(bytes)
		image, status := decode_and_validate_image(bytes)
		if status != .Ok { fmt.eprintln("invalid: ", status); os.exit(1) }
		code := make([]Instruction, int(image.sections[SECTION_CODE].count)); defer delete(code)
		if decode_code_words(&image, code) != .Ok { fmt.eprintln("invalid code"); os.exit(1) }
		data_size := max(1, int(image_resource(&image, 0)))
		return_size := max(1, int(image_resource(&image, 1)))
		heap_size := max(1, int(image_resource(&image, 2)))
		data := make([]Value, data_size); returns := make([]int, return_size); heap := make([]Value, heap_size)
		constants := make([]Value, int(image.sections[SECTION_CONSTANTS].count))
		defer delete(data); defer delete(returns); defer delete(heap); defer delete(constants)
		constant_bytes := section_words(&image, SECTION_CONSTANTS)
		for value, i in constants { _ = value; word, _ := word_at(constant_bytes, i); constants[i] = Value(word) }
		entry, found := image_entry_address(&image, 0); if !found { fmt.eprintln("error: image has no default entry"); os.exit(1) }
		target := Target_Config{feature_mask=KNOWN_FEATURES, data_words=u32(data_size), return_words=u32(return_size), heap_words=u32(heap_size)}
		if target_status := validate_target(&image, &target); target_status != .Ok { fmt.eprintln("target rejected image: ", target_status); os.exit(1) }
		iterations := u64(100); warmup := u64(10)
		for i := 3; i+1 < len(os.args); i += 2 {
			parsed, parse_ok := strconv.parse_u64(os.args[i+1]); if !parse_ok || parsed == 0 { fmt.eprintln("error: bad benchmark count"); os.exit(2) }
			if os.args[i] == "--iterations" { iterations = parsed } else if os.args[i] == "--warmup" { warmup = parsed } else { fmt.eprintln("error: unknown benchmark option: ", os.args[i]); os.exit(2) }
		}
		machine := Machine{data=data, returns=returns, heap=heap, constants=constants, fuel=u64(image_resource(&image, 4))}
		checksum := u64(0)
		for _ in 0..<warmup {
			result := run(code, &machine, entry); if result.status != .Ok { fmt.eprintln("status: ", result.status); os.exit(1) }
			checksum = checksum ~ u64(result.value)
		}
		start := time.tick_now()
		total_steps := u64(0)
		for _ in 0..<iterations {
			result := run(code, &machine, entry); if result.status != .Ok { fmt.eprintln("status: ", result.status); os.exit(1) }
			checksum = checksum ~ u64(result.value); total_steps += machine.steps
		}
		elapsed_ns := time.duration_nanoseconds(time.tick_since(start))
		fmt.printf("{{\"iterations\":%d,\"elapsed_ns\":%d,\"ns_per_op\":%.3f,\"steps_per_op\":%.3f,\"checksum\":%d}}\n",
			iterations, elapsed_ns, f64(elapsed_ns)/f64(iterations), f64(total_steps)/f64(iterations), checksum)
		return
	}
	if len(os.args) >= 7 && os.args[1] == "compile" && os.args[2] == "--profile" && os.args[5] == "--output" {
		profile := os.args[3]; input_path := os.args[4]; output_path := os.args[6]
		if profile != "core" && profile != "arena" && profile != "embedded" { fmt.eprintln("error: unsupported profile: ", profile); os.exit(2) }
		source, err := os.read_entire_file(input_path, context.allocator)
		if err != nil { fmt.eprintln("error: cannot read input: ", err); os.exit(2) }
		defer delete(source)
		compiled: Compile_Output
		result := compile_normalized(source, &compiled)
		if result.status != .Ok {
			fmt.eprintln("compile error: ", result.status, " at byte ", result.offset, " in ", result.function_name, ": ", result.construct)
			os.exit(1)
		}
		if profile == "core" && (compiled.resources[2] != 0 || compiled.import_count != 0) { fmt.eprintln("compile error: construct requires arena/embedded capability"); os.exit(1) }
		if profile == "arena" && compiled.import_count != 0 { fmt.eprintln("compile error: device import requires embedded capability"); os.exit(1) }
		spec := compiled_image_spec(&compiled)
		total, sized := image_size(&spec); if !sized { fmt.eprintln("compile error: image size overflow"); os.exit(1) }
		image_bytes := make([]u8, total); defer delete(image_bytes)
		written, encoded := encode_image(&spec, image_bytes); if encoded != .Ok { fmt.eprintln("compile error: image encoding failed"); os.exit(1) }
		if _, validated := decode_and_validate_image(image_bytes[:written]); validated != .Ok { fmt.eprintln("compile error: self-validation failed: ", validated); os.exit(1) }
		if write_err := os.write_entire_file(output_path, image_bytes[:written]); write_err != nil { fmt.eprintln("error: cannot write image: ", write_err); os.exit(2) }
		fmt.println("wrote ", written, " bytes; code-words=", compiled.code_count, " data-stack=", compiled.resources[0], " return-stack=", compiled.resources[1], " heap-words=", compiled.resources[2])
		return
	}
	fmt.println("usage: shen-joy compile --profile PROFILE INPUT --output IMAGE | inspect IMAGE | validate IMAGE | run IMAGE [--fuel N] | bench IMAGE [--iterations N] [--warmup N] | run-hex HEX | --demo")
}
