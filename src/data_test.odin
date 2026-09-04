package main

import "core:testing"

Mock_Device :: struct {
	adc: i64,
	last_gpio: i32,
	calls: int,
}

mock_device :: proc "odin" (primitive_id: u32, machine: ^Machine, ctx: rawptr) -> Status {
	device := (^Mock_Device)(ctx)
	switch primitive_id {
	case 1:
		value, ok := to_fixnum(device.adc); if !ok || !push(machine, value) { return .Stack_Limit }
	case 2:
		value, popped := pop_value(machine); if !popped { return .Bad_Image }
		n, fix := from_fixnum(value); if !fix { return .Type_Error }
		device.last_gpio = n
		if !push(machine, value) { return .Stack_Limit }
	case: return .Missing_Import
	}
	device.calls += 1
	return .Ok
}

@(test)
bounded_lists_and_vectors :: proc(t: ^testing.T) {
	list_source := `(program (function main () (head (cons 9 nil))) (entry main))`
	data: [512]Value; returns: [64]int; heap: [64]Value
	result, compiled := compile_and_run(list_source, data[:], returns[:], heap[:])
	n, fix := from_fixnum(result.value)
	testing.expect(t, compiled.status == .Ok && result.status == .Ok && fix && n == 9)
	vector_source := `(program (function main () (let V (vector 4) (let W (vector-set V 2 42) (vector-get W 2)))) (entry main))`
	result, compiled = compile_and_run(vector_source, data[:], returns[:], heap[:])
	n, fix = from_fixnum(result.value)
	testing.expect(t, compiled.status == .Ok && result.status == .Ok && fix && n == 42)
}

@(test)
arena_exhaustion_is_deterministic :: proc(t: ^testing.T) {
	program := [?]Instruction{encode(.Vector_New, 4), encode(.Halt)}
	data: [8]Value; returns: [3]int; heap: [4]Value
	machine := Machine{data=data[:], returns=returns[:], heap=heap[:]}
	result := run(program[:], &machine)
	testing.expect(t, result.status == .Heap_Limit)
}

@(test)
device_import_application_trace :: proc(t: ^testing.T) {
	source := `(program
  (import adc-read 1 0 1 effectful)
  (import gpio-write 2 1 1 effectful)
  (function classify (Sample) (if (< Sample 300) 0 (if (< Sample 700) 1 2)))
  (function main () (let Sample (device adc-read) (device gpio-write (classify Sample))))
  (entry main))`
	output: Compile_Output; compiled := compile_normalized(transmute([]u8)source, &output)
	spec := compiled_image_spec(&output); image_bytes: [131072]u8
	image_size, image_status := encode_image(&spec,image_bytes[:]); image, validated := decode_and_validate_image(image_bytes[:image_size])
	testing.expect(t,image_status==.Ok && validated==.Ok)
	missing_target := Target_Config{feature_mask=KNOWN_FEATURES,data_words=2048,return_words=64,heap_words=1}
	testing.expect(t,validate_target(&image,&missing_target)==.Missing_Import)
	primitive_ids := [?]u32{1,2}; supplied_target := missing_target; supplied_target.primitive_ids=primitive_ids[:]
	testing.expect(t,validate_target(&image,&supplied_target)==.Ok)
	data: [1024]Value; returns: [64]int; heap: [1]Value; device := Mock_Device{adc=650}
	machine := Machine{data=data[:], returns=returns[:], heap=heap[:], constants=output.constants[:output.constant_count], fuel=10000, device=mock_device, device_context=rawptr(&device)}
	result := run(output.code[:output.code_count], &machine, int(output.function_words[FUNCTION_WORDS+1]))
	n, fix := from_fixnum(result.value)
	testing.expect(t, compiled.status == .Ok && result.status == .Ok && fix && n == 1)
	testing.expect(t, device.calls == 2 && device.last_gpio == 1)
}

@(test)
arena_analysis_rejects_repeated_allocating_calls :: proc(t: ^testing.T) {
	source := `(program
  (function make-one (X) (cons X nil))
  (function main () (make-one 1))
  (entry main))`
	output: Compile_Output; result := compile_normalized(transmute([]u8)source,&output)
	testing.expect(t,result.status==.Unsupported_Construct)
}
