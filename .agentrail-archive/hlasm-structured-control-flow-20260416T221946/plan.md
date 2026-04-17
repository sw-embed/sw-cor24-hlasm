# Implementation Plan

## Status

The previous structured-control-flow saga was reseeded so the remaining work can
run in a correctness-first order.

Completed work already delivered:

- structured `IF / ELSE / ENDIF` core lowering
- nested structured `IF` plus `ELSEIF`
- structured `DO / DOEXIT / ITERATE / ENDDO` lowering
- tracked `reg-rs` `.out` baselines in git
- helper-ABI documentation plus `r2` callee-save audit script

## Approach

Keep `hlasm.s` target-native and incremental.

- preserve the existing UART-output model
- preserve the existing bootstrap input/config path
- prefer lowering to plain labels and branches rather than introducing a second
  output format
- harden correctness before broadening the feature surface when control-flow
  lowering depends on branch reach assumptions

## Step 1 -- Branch-range hardening

Audit structured control-flow lowering for branch distance limits and add
long-range-safe emission patterns where short `bra`/`brt`/`brf` targets may
overflow.

**Deliverable**: branch-range-safe structured IF and DO lowering.

**Test**: demos and regressions that force larger emitted blocks while still
producing correct control flow.

## Step 2 -- Structured SELECT lowering

Implement `SELECT / WHEN / OTHERWISE / ENDSEL` using the hardened structured
control-flow emission model.

**Deliverable**: select/when parser and lowering path.

**Test**: a demo and regression proving multi-arm dispatch and default-arm
behavior.

## Step 3 -- Integration pass

Run an integration pass across structured IF, DO, and SELECT together and
update docs/demos around the supported subset.

**Deliverable**: integrated structured-control-flow proof with updated feature
status across the repo docs.

**Test**: one larger regression that combines macros, conditional assembly, and
structured control flow in the same source.

## Deferred

- stronger macro parameter/default handling cleanup
- `COPY`/macro-library workflow beyond the current buffer/include bootstrap path
- `PROC/ENDP`
- `STRUCT/ENDSTRUCT`
- `REPT`
- listing mode and xref
- error recovery and diagnostics
- string `SET` symbols
