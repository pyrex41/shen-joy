# Build and design rules

- Use the pinned Nix flake for builds and tests. Do not rely on an ambient Odin compiler.
- Keep `src/vm.odin` allocation-free and free of OS, file, thread, and JIT dependencies.
- The device VM consumes validated images; malformed or unsupported programs return a status and must not panic.
- Do not turn the device runtime into a general Shen, Forth, or Joy reader/compiler. Host tools own parsing and lowering.
- Keep the 32-bit instruction and value encodings stable once an image-format version is released.
