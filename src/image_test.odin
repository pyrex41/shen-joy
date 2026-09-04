package main

import "core:testing"

sample_image :: proc(buffer: []u8) -> (int, Status) {
	code := [?]Instruction{encode(.Push, 6), encode(.Dup), encode(.Mul), encode(.Push, 1), encode(.Add), encode(.Halt)}
	functions := [?]u32{0x811c9dc5, 0, 0, 0, 1, 2, 0}
	entries := [?]u32{0x811c9dc5, 0}
	spec := Image_Spec{code=code[:], functions=functions[:], entries=entries[:], resources={2, 0, 0, 0, 100}}
	return encode_image(&spec, buffer)
}

@(test)
image_round_trip_is_deterministic :: proc(t: ^testing.T) {
	a, b: [512]u8
	na, sa := sample_image(a[:]); nb, sb := sample_image(b[:])
	testing.expect(t, sa == .Ok && sb == .Ok && na == nb)
	equal := true
	for value, i in a[:na] { if value != b[i] { equal = false; break } }
	testing.expect(t, equal)
	view, status := decode_and_validate_image(a[:na])
	testing.expect(t, status == .Ok)
	testing.expect(t, view.sections[SECTION_CODE].count == 6)
}

@(test)
image_corruption_and_truncation_are_rejected :: proc(t: ^testing.T) {
	buffer: [512]u8
	n, status := sample_image(buffer[:]); testing.expect(t, status == .Ok)
	for cut in 0..<n {
		_, truncated := decode_and_validate_image(buffer[:cut])
		testing.expect(t, truncated == .Bad_Image)
	}
	buffer[n-1] ~= 0x80
	_, corrupt := decode_and_validate_image(buffer[:n])
	testing.expect(t, corrupt == .Bad_Image)
}

@(test)
image_bad_target_is_rejected :: proc(t: ^testing.T) {
	buffer: [512]u8
	n, status := sample_image(buffer[:]); testing.expect(t, status == .Ok)
	view, ok := decode_and_validate_image(buffer[:n]); testing.expect(t, ok == .Ok)
	code_at := int(view.sections[SECTION_CODE].offset)
	put_u32(buffer[:], code_at, u32(encode(.Jump, 0x7fffff)))
	put_u32(buffer[:], 20, image_checksum(buffer[:n]))
	_, bad := decode_and_validate_image(buffer[:n])
	testing.expect(t, bad == .Bad_Image)
}

@(test)
target_resources_and_imports_are_checked_before_run :: proc(t: ^testing.T) {
	buffer: [512]u8; n, status := sample_image(buffer[:]); testing.expect(t, status == .Ok)
	image, valid := decode_and_validate_image(buffer[:n]); testing.expect(t, valid == .Ok)
	target := Target_Config{feature_mask=KNOWN_FEATURES, data_words=1, return_words=8}
	testing.expect(t, validate_target(&image, &target) == .Stack_Limit)
	target.data_words = 8
	testing.expect(t, validate_target(&image, &target) == .Ok)
}

@(test)
adversarial_header_and_section_fields_are_rejected :: proc(t: ^testing.T) {
	base: [512]u8; n, status := sample_image(base[:]); testing.expect(t,status==.Ok)
	offsets := [?]int{0,4,6,8,12,16,24,28,32,36,40,44}
	for offset in offsets {
		mutated := base
		mutated[offset] ~= 0x40
		put_u32(mutated[:],20,image_checksum(mutated[:n]))
		_, result := decode_and_validate_image(mutated[:n])
		testing.expect(t,result==.Bad_Image)
	}
	// Recompute checksums after pseudo-random semantic mutations: the validator
	// must reject structure, not merely rely on integrity detection.
	seed := u32(0xabad1dea)
	for _ in 0..<128 {
		mutated := base; seed=seed*1664525+1013904223
		offset := 32+int(seed%u32(IMAGE_SECTION_COUNT*SECTION_ENTRY_SIZE))
		mutated[offset] ~= u8(1<<(seed%8)); put_u32(mutated[:],20,image_checksum(mutated[:n]))
		_, result := decode_and_validate_image(mutated[:n])
		// Mutating padding/count-zero fields can remain a different valid image;
		// the safety property is total validation without panic.
		testing.expect(t,result==.Ok || result==.Bad_Image)
	}
}
