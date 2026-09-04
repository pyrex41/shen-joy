.PHONY: all build test run clean

all: test

build:
	nix develop path:. --command ./scripts/build.sh

test:
	nix flake check path:.

run:
	nix run path:. -- --demo

clean:
	rm -rf build
