#!/usr/bin/env bash
set -euo pipefail

# sw-cor24-hlasm -- Build script
# Usage:
#   ./build.sh              Assemble check only
#   ./build.sh run          Build and run on emulator
#   ./build.sh bootstrap    Build and run a bootstrap source set
#   ./build.sh test         Run test suite
#   ./build.sh clean        Remove build artifacts

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

HLASM="hlasm.s"
# Every hlasm run goes through scripts/run-kernel.sh, which finds cor24-asm
# (sw-cor24-x-assembler) and cor24-emu (sw-cor24-emulator) on PATH or in the
# sibling checkouts and says which is missing.
RUN="scripts/run-kernel.sh"

if [[ ! -f "$HLASM" ]]; then
    echo "ERROR: $HLASM not found."
    exit 1
fi

build() {
    echo "=== Assembling $HLASM ==="
    $RUN "$HLASM" --speed 0 -n 1000 2>&1 | tail -5
    echo "Assemble check OK."
}

run() {
    build
    echo ""
    echo "=== Running ==="
    $RUN "$HLASM" --speed 0 "$@"
}

bootstrap_run() {
    local sourceset="${2:-bootstrap/hlasm0.sourceset}"
    local max_insns="${3:-1000000}"

    build
    echo ""
    echo "=== Bootstrap Source Set ==="
    bash reg-rs/run_bootstrap_sourceset.sh "$sourceset" "$max_insns"
}

test_suite() {
    echo "=== sw-cor24-hlasm Test Suite ==="
    if ! command -v reg-rs &>/dev/null; then
        echo "ERROR: reg-rs not found."
        exit 1
    fi
    REG_RS_DATA_DIR="$SCRIPT_DIR/reg-rs" reg-rs run -p hlasm_ --parallel
}

clean() {
    rm -rf build/
    echo "Cleaned."
}

CMD="${1:-build}"

case "$CMD" in
    build)  build ;;
    run)    shift; run "$@" ;;
    bootstrap) bootstrap_run "$@" ;;
    test)   test_suite ;;
    clean)  clean ;;
    *)      echo "Usage: $0 {build|run|bootstrap|test|clean}"; exit 1 ;;
esac
