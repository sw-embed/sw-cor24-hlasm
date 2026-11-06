#!/usr/bin/env bash
# check_expr_errors.sh -- expression and string-escape errors stop with ERROR.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hlasm-expr.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# run <label> <source text>: run hlasm and print its ERROR line (or "ok").
run() {
    printf '%s\n' "$2" > "$WORK/$1.hlasm"
    bash demos/make_bin.sh "$WORK/$1.hlasm" "$WORK/$1.bin" >/dev/null
    scripts/run-kernel.sh hlasm.s --load-binary "$WORK/$1.bin@524288" \
        --speed 0 -n 400000 -q > "$WORK/$1.out" 2>&1 || true
    if grep -q '^ERROR:' "$WORK/$1.out"; then
        printf '%s: %s\n' "$1" "$(grep -m1 '^ERROR:' "$WORK/$1.out" | tr -d '\r')"
    else
        printf '%s: ok: %s\n' "$1" "$(tr -d '\r' < "$WORK/$1.out" | grep -v '^Executed' | grep . | tail -1)"
    fi
}

run div_zero 'X EQU 1/0'
run mod_zero 'X EQU 7%(2-2)'
run str_bad_escape '.ascii "a\q"'
run str_bad_hex '.ascii "\xZ1"'
run char_bad_escape ' lc r0,'"'"'\q'"'"''
run str_good '.asciz "\x41\\\"\t"'
run char_good ' lc r0,'"'"'\n'"'"'+1'
