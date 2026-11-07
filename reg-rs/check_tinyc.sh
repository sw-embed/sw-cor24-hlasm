#!/usr/bin/env bash
# check_tinyc.sh <demo> -- run a tiny-C demo ported to hlasm
# (demos/tinyc/<demo>.sourceset) end to end and print its UART output,
# which ends with "r0=<n>", the value main returned. Demos that drive the
# LED also print the final LED state that cor24-emu reports; button runs
# with S2 released and pressed; demo9 gets the UART input "A".
# See docs/c-demos-in-hlasm.md.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hlasm-tinyc.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

demo="${1:?usage: $0 <demo>}"
set_file="demos/tinyc/$demo.sourceset"

# led_state: the final LED state of the generated program
led_state() {
    scripts/run-kernel.sh "$WORK/out.s" --speed 0 -n 1000000 2>&1 \
        | grep '^\[LED' | sed 's/ @ [0-9]*\]/]/' || echo "[LED] not written"
}

case "$demo" in
    button)
        echo "released: $(scripts/hlasm-e2e.sh "$set_file")"
        echo "pressed: $(scripts/hlasm-e2e.sh "$set_file" -- --switch on)"
        ;;
    demo9)
        scripts/hlasm-e2e.sh "$set_file" -- -u A
        ;;
    led|demo2|demo8|demo10)
        scripts/hlasm-e2e.sh --keep-s "$WORK/out.s" "$set_file"
        led_state
        ;;
    *)
        scripts/hlasm-e2e.sh "$set_file"
        ;;
esac
