#!/usr/bin/env bash
# check_conditions.sh -- condition-name, IFEQ/IFNE operand and IFSAME/IFDIFF
# edge cases. Prints each case's ERROR line, or "ok" and hlasm's output
# lines joined with "|".
# See docs/limits-and-lifting-plan.md (M8, M9).
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hlasm-cond.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# run <label> <source text>
run() {
    printf '%s\n' "$2" > "$WORK/$1.hlasm"
    bash demos/make_bin.sh "$WORK/$1.hlasm" "$WORK/$1.bin" >/dev/null
    scripts/run-kernel.sh hlasm.s --load-binary "$WORK/$1.bin@524288" \
        --speed 0 -n 2000000 -q > "$WORK/$1.out" 2>&1 || true
    if grep -q '^ERROR:' "$WORK/$1.out"; then
        printf '%s: %s\n' "$1" "$(grep -m1 '^ERROR:' "$WORK/$1.out" | tr -d '\r')"
    else
        printf '%s: ok: %s\n' "$1" "$(tr -d '\r' < "$WORK/$1.out" \
            | grep -v -e '^Executed' -e '^Loaded ' | grep . | paste -s -d '|' -)"
    fi
}

# unknown condition names stop in IF, ELSEIF and DOEXIT
run if_bad_cc $'IF cc_foo,r0,1\n nop\nENDIF'
run elseif_bad_cc $'IF cc_eq,r0,1\nELSEIF cc_lte,r0,2\nENDIF'
run doexit_bad_cc $'DO\n DOEXIT cc_gte,r0,1\nENDDO'

# a swapped compare against z uses the constant 0 (cls z,r0 does not exist)
run gt_z $'IF cc_gt,r0,z\n nop\nENDIF'
run le_reg $'IF cc_leu,r0,r1\n nop\nENDIF'

# IFEQ/IFNE take SET/EQU symbols and numbers; other names stop, except in a
# skipped region
run ifeq_undef $'IFEQ NOPE,1\n nop\nENDIFASM'
run ifne_register $'IFNE r2,0\n nop\nENDIFASM'
run ifeq_skipped $'IFDEF NOPE\nIFEQ NOPE,1\n nop ; inner\nENDIFASM\nENDIFASM\n nop ; after'
run ifeq_defined $'SET K,3\nIFEQ K,3\n nop ; k3\nENDIFASM'

# IFSAME/IFDIFF compare text exactly
run same_reg $'MACRO M &A\nIFSAME &A,r2\n nop ; reg\nELSEASM\n nop ; other\nENDIFASM\nMEND\n M r2\n M 5\n M R2\n M r22'
run same_empty $'IFSAME ,\n nop ; both empty\nENDIFASM\nIFSAME x,\n nop ; wrong\nENDIFASM'
run same_quoted $'IFSAME \'a,b\',\'a,b\'\n nop ; quoted\nENDIFASM\nIFDIFF (r1,r2),(r1, r2)\n nop ; differ\nENDIFASM'
run diff_blanks $'IFDIFF  r1 , r1 \n nop ; wrong\nELSEASM\n nop ; same\nENDIFASM'
