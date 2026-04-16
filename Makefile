# Makefile -- sw-cor24-hlasm
# Minimal Makefile following sw-cor24-forth convention.

.PHONY: all test demo clean

all:
	./build.sh build

test:
	./build.sh test

demo:
	./demo.sh

clean:
	./build.sh clean
