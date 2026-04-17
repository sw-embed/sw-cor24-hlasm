#!/usr/bin/env bash
# demo.sh -- Run sw-cor24-hlasm demos
# Usage:
#   ./demo.sh           Run automated demo
#   ./demo.sh test      Run test suite
#   ./demo.sh bootstrap Run bootstrap source-set proof
#   ./demo.sh repl      Interactive (future)

set -euo pipefail
cd "$(dirname "$0")"

HLASM="hlasm.s"
RUN="cor24-run --run $HLASM --speed 0"

case "${1:-demo}" in
    test)
        exec ./build.sh test
        ;;
    bootstrap)
        echo "=== sw-cor24-hlasm Bootstrap Demo ==="
        echo ""
        ./build.sh bootstrap bootstrap/hlasm0.sourceset 120000 2>&1 \
            | grep "^UART output:" -A 20 | tr '\n' ' ' \
            | sed -e 's/.*UART output: //' -e 's/Executed.*//' \
            | sed -e 's/  */ /g' -e 's/^ //;s/ $//'
        echo ""
        echo "To run tests: ./demo.sh test"
        ;;
    repl)
        echo "=== sw-cor24-hlasm REPL (not yet implemented) ==="
        echo ""
        cor24-run --run "$HLASM" --terminal --echo --speed 0
        ;;
    demo)
        echo "=== sw-cor24-hlasm Demo ==="
        echo ""
        if [[ ! -f "$HLASM" ]]; then
            echo "hlasm.s not yet created."
            exit 1
        fi
        $RUN -n 5000000 2>&1 | grep "^UART output:" -A 20 | tr '\n' ' ' \
            | sed -e 's/.*UART output: //' -e 's/Executed.*//' \
            | sed -e 's/  */ /g' -e 's/^ //;s/ $//'
        echo ""
        echo "To run tests: ./demo.sh test"
        ;;
    *)
        echo "Usage: $0 [demo|test|bootstrap|repl]"
        exit 1
        ;;
esac
