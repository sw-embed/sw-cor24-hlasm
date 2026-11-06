#!/usr/bin/env bash
# check_limits.sh <table> -- exercise one hlasm capacity limit.
#
# For each table this generates two sources, one exactly at the limit and
# one just past it, runs hlasm on each (through the sourceset runner, so the
# main source may be larger than the default 32 KB window), and prints
# either "ok" with the output line count or the "ERROR: ..." line that
# _fatal printed. See docs/limits-and-lifting-plan.md.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hlasm-limits.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# rep <count> <char>: print <char> <count> times.
rep() {
    local s=""
    local i
    for ((i = 0; i < $1; i++)); do s="$s$2"; done
    printf '%s' "$s"
}

# name <len>: an identifier of exactly <len> characters.
name() {
    printf 'N%s' "$(rep $(( $1 - 1 )) A)"
}

# run <label> <budget>: run hlasm on $WORK/<label>.hlasm and summarize.
run() {
    local label="$1"
    local budget="$2"
    printf 'MAIN %s\n' "$WORK/$label.hlasm" > "$WORK/$label.sourceset"
    bash reg-rs/run_bootstrap_sourceset.sh "$WORK/$label.sourceset" \
        "$budget" -q > "$WORK/$label.out" 2>&1 || true
    tr -d '\r' < "$WORK/$label.out" | grep -v -e '^Executed' -e '^Loaded ' \
        > "$WORK/$label.txt" || true
    if grep -q '^ERROR:' "$WORK/$label.txt"; then
        printf '%s: %s\n' "$label" "$(grep -m1 '^ERROR:' "$WORK/$label.txt")"
    else
        printf '%s: ok, %s output lines, last: %s\n' "$label" \
            "$(grep -c . "$WORK/$label.txt" || true)" \
            "$(grep . "$WORK/$label.txt" | tail -1 | cut -c1-40)"
    fi
}

# gen_* <count>: write a source with <count> items to stdout.
gen_line() {
    printf ';%s\n nop\n' "$(rep $(( $1 - 1 )) x)"
}

gen_symname() {
    printf 'SET %s,1\nIFDEF %s\n nop\nENDIFASM\n' "$(name "$1")" "$(name "$1")"
}

gen_symbols() {
    local i
    for ((i = 1; i <= $1; i++)); do printf 'SET S%d,%d\n' "$i" "$i"; done
    printf 'IFEQ S%d,%d\n nop\nENDIFASM\n' "$1" "$1"
}

gen_macname() {
    printf 'MACRO %s\n nop\nMEND\n%s\n' "$(name "$1")" "$(name "$1")"
}

gen_macros() {
    local i
    for ((i = 1; i <= $1; i++)); do printf 'MACRO M%d\n nop\nMEND\n' "$i"; done
    printf 'M%d\n' "$1"
}

gen_params() {
    local i
    local hdr=""
    local call=""
    for ((i = 1; i <= $1; i++)); do
        hdr="$hdr${hdr:+,}&P$i"
        call="$call${call:+,}$i"
    done
    printf 'MACRO PM %s\n add r0,&P%d\nMEND\nPM %s\n' "$hdr" "$1" "$call"
}

gen_parmname() {
    local p
    p="$(name "$1")"
    printf 'MACRO PN &%s\n add r0,&%s\nMEND\nPN 1\n' "$p" "$p"
}

# Each body line is 250 characters and takes 251 bytes of the 64 KB pool.
gen_pool() {
    local i
    local body
    body=";$(rep 249 x)"
    printf 'MACRO BIG\n'
    for ((i = 1; i <= $1; i++)); do printf '%s\n' "$body"; done
    printf 'MEND\n'
}

# Expanded line " nop ;<arg>" is 6 + <arg> characters.
gen_expand() {
    printf 'MACRO EX &A\n nop ;&A\nMEND\nEX %s\n' "$(rep $(( $1 - 6 )) y)"
}

# Macro call depth <n>: R calls itself until &N is 1.
gen_macdepth() {
    printf 'MACRO R &N\nIFNE &N,1\n R &N-1\nENDIFASM\n nop ;&N\nMEND\nR %d\n' "$1"
}

gen_args() {
    local i
    local call=""
    for ((i = 1; i <= $1; i++)); do call="$call${call:+,}$i"; done
    printf 'MACRO AR\n nop ;&SYSNARG\nMEND\nAR %s\n' "$call"
}

gen_default() {
    printf 'MACRO DF &X=%s\n nop ;&X\nMEND\nDF\n' "$(rep "$1" z)"
}

gen_cond() {
    local i
    printf 'SET ON,1\n'
    for ((i = 1; i <= $1; i++)); do printf 'IFDEF ON\n'; done
    printf ' nop\n'
    for ((i = 1; i <= $1; i++)); do printf 'ENDIFASM\n'; done
}

gen_if() {
    local i
    for ((i = 1; i <= $1; i++)); do printf 'IF cc_eq, r0, 0\n'; done
    printf ' nop\n'
    for ((i = 1; i <= $1; i++)); do printf 'ENDIF\n'; done
}

gen_do() {
    local i
    for ((i = 1; i <= $1; i++)); do printf 'DO\n DOEXIT cc_eq, r0, 0\n'; done
    for ((i = 1; i <= $1; i++)); do printf 'ENDDO\n'; done
}

gen_select() {
    local i
    for ((i = 1; i <= $1; i++)); do printf 'SELECT r0\nWHEN 1\n'; done
    printf ' nop\n'
    for ((i = 1; i <= $1; i++)); do printf 'ENDSEL\n'; done
}

# Structured label ids past 999 (each IF uses 3 ids): the output must still
# assemble.
gen_labels() {
    local i
    for ((i = 1; i <= $1; i++)); do printf 'IF cc_eq, r0, 1\n add r1,1\nENDIF\n'; done
    printf '_h:\n bra _h\n'
}

# case <table> <at-limit> <past-limit> <budget>
case_pair() {
    "gen_$1" "$2" > "$WORK/$1_at_$2.hlasm"
    run "$1_at_$2" "$4"
    "gen_$1" "$3" > "$WORK/$1_over_$3.hlasm"
    run "$1_over_$3" "$4"
}

case "${1:-}" in
    line)     case_pair line 256 257 400000 ;;
    symname)  case_pair symname 31 32 400000 ;;
    symbols)  case_pair symbols 512 513 60000000 ;;
    macname)  case_pair macname 31 32 400000 ;;
    macros)   case_pair macros 256 257 60000000 ;;
    params)   case_pair params 16 17 800000 ;;
    parmname) case_pair parmname 31 32 400000 ;;
    pool)     case_pair pool 261 262 60000000 ;;
    expand)   case_pair expand 256 257 400000 ;;
    macdepth) case_pair macdepth 8 9 2000000 ;;
    args)     case_pair args 16 17 800000 ;;
    default)  case_pair default 63 64 400000 ;;
    cond)     case_pair cond 32 33 2000000 ;;
    if)       case_pair if 32 33 4000000 ;;
    do)       case_pair do 32 33 4000000 ;;
    select)   case_pair select 32 33 4000000 ;;
    labels)
        gen_labels 400 > "$WORK/labels_400.hlasm"
        run labels_400 30000000
        cp "$WORK/labels_400.txt" "$WORK/labels_400.s"
        if scripts/run-kernel.sh "$WORK/labels_400.s" --speed 0 -n 1 -q \
            > "$WORK/labels_asm.log" 2>&1; then
            echo "labels_400: output assembles"
        else
            echo "labels_400: assembly errors"
            grep 'Line [0-9]*:' "$WORK/labels_asm.log" | head -5
        fi
        printf 'labels_400: highest label id %s\n' \
            "$(grep -o '_hlif_[0-9]*_' "$WORK/labels_400.txt" | tr -dc '0-9\n' | sort -n | tail -1)"
        ;;
    *)
        echo "Usage: $0 line|symname|symbols|macname|macros|params|parmname|pool|expand|macdepth|args|default|cond|if|do|select|labels"
        exit 1
        ;;
esac
