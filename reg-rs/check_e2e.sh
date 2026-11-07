#!/usr/bin/env bash
# check_e2e.sh -- exercise scripts/hlasm-e2e.sh beyond a single .hlasm file.
#
# Prints one line per case: the program's UART output, or the harness exit
# status for the failure cases.
#   copy      a sourceset whose main COPYs a macro library member; the
#             macros print "COPY ok"
#   hlasm     an hlasm ERROR stops at stage 1 (exit 2)
#   asm       output cor24-asm rejects stops at stage 2 (exit 3)
#   halt      a program that never halts stops at stage 3 (exit 4)
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hlasm-e2e-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# status <case> <harness args...>: print the harness exit status.
status() {
    local name="$1" rc=0
    shift
    scripts/hlasm-e2e.sh "$@" > /dev/null 2>&1 || rc=$?
    echo "$name: exit $rc"
}

cat > "$WORK/lib.hlasm" <<'EOF'
; library member: UART output macros
UART EQU -65280
MACRO PUTCH &C
L\@:
 lb r1,1(r2)
 cls r1,z
 brt L\@
 lc r0,&C
 sb r0,0(r2)
MEND
EOF
cat > "$WORK/main.hlasm" <<'EOF'
; main: uses the library through COPY
COPY iolib
 la r2,UART
 PUTCH 'C'
 PUTCH 'O'
 PUTCH 'P'
 PUTCH 'Y'
 PUTCH ' '
 PUTCH 'o'
 PUTCH 'k'
halt:
 bra halt
EOF
printf 'ROOT .\nMAIN main.hlasm\nCOPY iolib lib.hlasm\n' > "$WORK/set.sourceset"
echo "copy: $(scripts/hlasm-e2e.sh "$WORK/set.sourceset")"

printf 'SET X,1/0\n' > "$WORK/bad.hlasm"
status hlasm "$WORK/bad.hlasm"

printf ' bogus r0,1\n' > "$WORK/asm.hlasm"
status asm "$WORK/asm.hlasm"

printf 'L:\n add r0,1\n bra L\n' > "$WORK/spin.hlasm"
status halt --run-n 5000 "$WORK/spin.hlasm"
