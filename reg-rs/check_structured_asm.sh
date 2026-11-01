#!/usr/bin/env bash
# check_structured_asm.sh -- assemble hlasm's output for each structured demo.
#
# reg-rs compares hlasm's text output, which by itself never proved that the
# output assembles. For every demo below, run hlasm (via its reg-rs command,
# with -q for plain UART text), feed the result to cor24-asm through
# scripts/run-kernel.sh, and report "ok" or the assembler's errors.
#
# Every demo is expected to report "ok"; any assembler error stays visible in
# the baseline rather than being filtered out.
set -euo pipefail
cd "$(dirname "$0")/.."

DEMOS="d11_structured_if d12_structured_do d13_structured_select
d26_branch_range_hardening d29_control_flow_integration
d30_structured_annotations d32_literals_and_data d35_listing_xref
d36_structured_elseif_no_else d40_long_range_jumps"

WORK="$(mktemp -d -t hlasm-asm-check)"
trap 'rm -rf "$WORK"' EXIT

for demo in $DEMOS; do
    rgt="reg-rs/hlasm_${demo}.rgt"
    cmd="$(grep '^command' "$rgt" | sed -e 's/^command = "//' -e 's/ 2>&1"$//')"
    bash -c "$cmd -q" 2>/dev/null > "$WORK/$demo.s"

    if scripts/run-kernel.sh "$WORK/$demo.s" --speed 0 -n 1 -q \
        > "$WORK/$demo.log" 2>&1; then
        echo "$demo: ok"
    else
        echo "$demo: errors"
        grep 'Line [0-9]*:' "$WORK/$demo.log" | sed 's/^.*: Line /  Line /'
    fi
done
