#!/usr/bin/env bash
# check_lib.sh <case> -- run a macro-library test program from demos/libtest
# end to end (scripts/hlasm-e2e.sh) and print what it prints.
#
#   console  PUTC PUTNL PUTS WTO PUTDEC PUTHEX STR START SHOWRC
#   frame    PROLOG RET RETURN ARG LOCAL CALL (0-3 args, r0/r2 targets) EXIT
#   rt       DIV MOD RTCALL strlen strcmp strcpy memcpy memset atoi, SPACE
#   io       GETC GETLINE (UART input "Zab cd\nrest\n") GETMAIN FREEMAIN
#   check    CHECKINIT CHECK CHECKEND (passing and failing), WORDS BYTES
#            SPACE STR
#   board    BUTTON with S2 released and pressed; the final LED state after
#            LEDON, LEDOFF, LEDON (cor24-emu logs the state at the end)
#   struct   DSECT/FIELD/DEND misuse and the ERROR directive
# See lib/*.hlasm and docs/c-demos-in-hlasm.md.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hlasm-lib.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

e2e() {
    scripts/hlasm-e2e.sh "$@"
}

case "${1:-}" in
    console|frame|rt)
        e2e "demos/libtest/$1.sourceset"
        ;;
    io)
        e2e demos/libtest/io.sourceset -- -u 'Zab cd\nrest\n'
        ;;
    check)
        e2e demos/libtest/check.sourceset
        e2e demos/libtest/checkfail.sourceset
        ;;
    board)
        echo "released: $(e2e demos/libtest/board.sourceset -- --switch off)"
        echo "pressed: $(e2e --keep-s "$WORK/board.s" demos/libtest/board.sourceset -- --switch on)"
        scripts/run-kernel.sh "$WORK/board.s" --speed 0 -n 100000 2>&1 \
            | grep '^\[LED' | sed 's/ @ [0-9]*\]/]/'
        ;;
    struct)
        # each misuse stops with the ERROR line that names it
        for c in "FIELD x,3" "DSECT a|DSECT b" "DEND a" "DSECT a|FIELD a_x,3|DEND a|ERROR 'custom message'"; do
            printf '%s\n' "COPY struct" > "$WORK/s.hlasm"
            printf '%s\n' "$c" | tr '|' '\n' >> "$WORK/s.hlasm"
            printf 'ROOT /\nMAIN %s\nSOURCESET %s\n' "$WORK/s.hlasm" "$PWD/lib/lib.sourceset" > "$WORK/s.sourceset"
            echo "$c: $( { e2e "$WORK/s.sourceset" 2>&1 || true; } | grep -m1 '^ERROR' || true)"
        done
        ;;
    *)
        echo "usage: $0 console|frame|rt|io|check|board|struct" >&2
        exit 2
        ;;
esac
