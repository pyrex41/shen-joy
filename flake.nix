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
        in { default = shen-joy; inherit shen-joy odin; });
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
        in {
          inherit package;
          # The package derivation runs the Odin unit tests before building,
          # so this check cannot accidentally validate a different toolchain.
          unit = package;
          demo = pkgs.runCommand "shen-joy-demo" { } ''
            test "$(${package}/bin/shen-joy --demo)" = 37
            touch $out
          '';
        });
    };
}
