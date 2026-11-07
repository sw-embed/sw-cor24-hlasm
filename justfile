# justfile -- sw-cor24-hlasm

build:
    ./build.sh build

test:
    ./build.sh test

demo:
    ./demo.sh

bootstrap:
    ./build.sh bootstrap bootstrap/hlasm0.sourceset 1000000

clean:
    ./build.sh clean
