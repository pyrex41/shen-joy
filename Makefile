.PHONY: all build test run clean

all: test

build:
	./scripts/build.sh

test:
	odin test src

run: build
	./build/shen-joy --demo

clean:
	rm -rf build
