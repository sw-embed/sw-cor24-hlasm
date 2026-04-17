# Calling Convention Audit

Internal helper routines in `hlasm.s` now use the stricter convention documented
in `docs/architecture.md`:

- `r0`: return value and caller-saved scratch
- `r1`: return address and volatile scratch
- `r2`: callee-saved working register
- `fp` and `sp`: restored by callee

## What This Step Fixed

The following helpers were updated to preserve `r2` correctly while still using
it internally:

- `_emit_char`
- `_emit_strz`
- `_mul3`
- `_mul6`
- `_mul9`
- `_mul10`
- `_mul15`

These fixes also required correcting argument offsets for helpers whose frame
size changed after adding `push r2`.

## Audit Tool

Use:

```sh
bash reg-rs/audit_calling_convention.sh
```

The audit script:

- finds function entries by looking for labels whose first few lines include
  `push fp`
- treats `r2` as a violation target only in executable lines, not comments
- reports helpers that use `r2` without both `push r2` and `pop r2`

## Current Status

Current audit result: no `r2` callee-save violations detected by the script.

This is a focused defensive check, not a full ABI proof. It currently audits
only the `r2` preservation rule and does not prove:

- argument offsets are correct in every helper
- `r0` and `r1` are only used as volatile registers
- every caller handles caller-saved values correctly
- stack depth remains balanced on every control-flow path

Those wider ABI checks remain future hardening work.
