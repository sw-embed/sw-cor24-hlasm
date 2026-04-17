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
RUN="cor24-run"

if ! command -v cor24-run &>/dev/null; then
    echo "ERROR: cor24-run not found. Build sw-cor24-emulator first."
    exit 1
fi

if [[ ! -f "$HLASM" ]]; then
    echo "ERROR: $HLASM not found."
    exit 1
fi

build() {
    echo "=== Assembling $HLASM ==="
    $RUN --run "$HLASM" --speed 0 -n 1000 2>&1 | tail -5
    echo "Assemble check OK."
}

run() {
    build
    echo ""
    echo "=== Running ==="
    $RUN --run "$HLASM" --speed 0 "${@:2}"
}

bootstrap_run() {
    local sourceset="${2:-bootstrap/hlasm0.sourceset}"
    local max_insns="${3:-120000}"

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
