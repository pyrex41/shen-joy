{
  description = "shen-joy — bounded Shen-derived concatenative VM";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    odin-src = {
      url = "github:odin-lang/Odin/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, odin-src }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAll (system:
        let
          pkgs = import nixpkgs { inherit system; };
          odin = pkgs.callPackage ./nix/odin.nix {
            src = odin-src;
            llvmPackages_22 = pkgs.llvmPackages_22;
          };
          shen-joy = pkgs.callPackage ./nix/shen-joy.nix { inherit odin; };
          # Differential reference: Shen/CL v3.2.0 on ShenOSKernel 43.1
          # (see PROVENANCE.md). Archives are pinned by SHA-256 in the derivation.
          shen-reference = pkgs.callPackage ./nix/shen-reference.nix { };
          mcu-runtime = pkgs.runCommand "shen-joy-rp2040-runtime" { nativeBuildInputs = [ pkgs.llvmPackages_22.clang-unwrapped ]; } ''
            mkdir -p $out/lib $out/include
            clang --target=armv6m-none-eabi -std=c99 -Oz -ffreestanding -fno-builtin -nostdlib -I${./runtime/c} \
              -c ${./runtime/c/shen_joy_vm.c} -o $out/lib/shen_joy_vm.o
            cp ${./runtime/c/shen_joy_vm.h} $out/include/
            ${pkgs.llvmPackages_22.llvm}/bin/llvm-size $out/lib/shen_joy_vm.o > $out/resource.txt
            printf '%s\n' 'target=armv6m-none-eabi' 'compiler=clang-22' > $out/toolchain.txt
          '';
          toolchain = pkgs.buildEnv {
            name = "shen-joy-toolchain";
            paths = [ shen-joy odin pkgs.gnumake ];
          };
        in { default = shen-joy; inherit shen-joy odin shen-reference mcu-runtime toolchain; });
      apps = forAll (system: {
        default = { type = "app"; program = "${self.packages.${system}.shen-joy}/bin/shen-joy"; };
      });
      devShells = forAll (system:
        let pkgs = import nixpkgs { inherit system; };
        in { default = pkgs.mkShell { packages = [ self.packages.${system}.odin pkgs.gnumake ]; }; });
      checks = forAll (system:
        let
          pkgs = import nixpkgs { inherit system; };
          package = self.packages.${system}.shen-joy;
          shen-reference = self.packages.${system}.shen-reference;
        in {
          inherit package;
          # The package derivation runs the Odin unit tests before building,
          # so this check cannot accidentally validate a different toolchain.
          unit = package;
          demo = pkgs.runCommand "shen-joy-demo" { } ''
            test "$(${package}/bin/shen-joy --demo)" = 37
            touch $out
          '';
          differential = pkgs.runCommand "shen-joy-differential" { nativeBuildInputs = [ package shen-reference ]; } ''
            cp ${./tests/differential.sjk} program.sjk
            shen-joy compile --profile core program.sjk --output program.sji >/dev/null
            actual="$(shen-joy run program.sji)"
            expected="$(shen-reference eval -l ${./tests/differential.shen} | sed -n 's/^SJ_RESULT=//p' | head -n1)"
            test "$actual" = "$expected"
            cp ${./tests/data-differential.sjk} data.sjk
            shen-joy compile --profile arena data.sjk --output data.sji >/dev/null
            actual="$(shen-joy run data.sji)"
            expected="$(shen-reference eval -l ${./tests/data-differential.shen} | sed -n 's/^SJ_RESULT=//p' | head -n1)"
            test "$actual" = "$expected"
            touch $out
          '';
          conformance = pkgs.runCommand "shen-joy-cross-conformance" { nativeBuildInputs = [ package pkgs.stdenv.cc pkgs.iverilog pkgs.yosys ]; } ''
            mkdir -p conformance runtime/c rtl
            cp ${./conformance/core.hex} conformance/core.hex
            cp ${./conformance/branch.hex} conformance/branch.hex
            cp ${./conformance/overflow.hex} conformance/overflow.hex
            cp ${./runtime/c/shen_joy_vm.c} runtime/c/shen_joy_vm.c
            cp ${./runtime/c/shen_joy_vm.h} runtime/c/shen_joy_vm.h
            cp ${./runtime/c/conformance.c} runtime/c/conformance.c
            cp ${./rtl/shen_joy_core.sv} rtl/shen_joy_core.sv
            cp ${./rtl/conformance_tb.sv} rtl/conformance_tb.sv
            cc -std=c99 -Wall -Wextra -Werror runtime/c/shen_joy_vm.c runtime/c/conformance.c -o c-conformance
            mkdir -p $out
            for vector in core branch overflow; do
              case "$vector" in
                core) expected=37; expected_status=0; expected_steps=6 ;;
                branch) expected=42; expected_status=0; expected_steps=4 ;;
                overflow) expected=0; expected_status=5; expected_steps=3 ;;
              esac
              c_result="$(./c-conformance conformance/$vector.hex)"
              odin_result="$(shen-joy run-hex conformance/$vector.hex)"
              iverilog -g2012 -s conformance_tb \
                -Pconformance_tb.CODE_FILE=\"conformance/$vector.hex\" \
                -Pconformance_tb.EXPECTED=$expected -Pconformance_tb.EXPECTED_STATUS=$expected_status \
                -Pconformance_tb.EXPECTED_STEPS=$expected_steps \
                -o rtl-sim rtl/shen_joy_core.sv rtl/conformance_tb.sv
              rtl_result="$(vvp rtl-sim | sed -n '/RESULT=/p' | head -n1)"
              test "$c_result" = "$odin_result"
              test "$rtl_result" = "$odin_result"
              printf '%s %s\n' "$vector" "$odin_result" >> $out/traces.txt
            done
            yosys -p 'read_verilog -sv rtl/shen_joy_core.sv; synth -top shen_joy_core; stat' > $out/synthesis.txt
          '';
          mcu = self.packages.${system}.mcu-runtime;
        });
    };
}
