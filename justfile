# justfile -- sw-cor24-hlasm

build:
    ./build.sh build

test:
    ./build.sh test

demo:
    ./demo.sh

clean:
    ./build.sh clean
