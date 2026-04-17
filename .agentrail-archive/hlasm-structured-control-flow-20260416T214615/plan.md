# Implementation Plan

## Status

`hlasm-phase1` is complete and archived.

That saga delivered:

- plain-assembly passthrough
- macro definition and expansion
- assembly-time conditionals: `SET`, `IFDEF`, `IFNDEF`, `IFEQ`, `IFNE`,
  `ELSEASM`, `ENDIFASM`
- multi-buffer source input
- `SRCBUF`, `INCBUF`, and named `INCLUDE`
- bootstrap-oriented low-SRAM config loading
- composed bootstrap source sets with profiles and fragments

The active saga is now focused on structured control flow plus correctness
hardening for the emitted branch model:

- `IF / ELSEIF / ELSE / ENDIF`
- `DO / DOEXIT / ITERATE / ENDDO`
- branch-range-safe lowering for structured control flow
- `SELECT / WHEN / OTHERWISE / ENDSEL`

## Approach

Keep `hlasm.s` target-native and incremental.

- preserve the existing UART-output model
- preserve the existing bootstrap input/config path
- add one structured family at a time, each with a demo, a `reg-rs` proof, and
  a docs update
- prefer lowering to plain labels and branches rather than introducing a second
  output format
- harden correctness before broadening the feature surface when control-flow
  lowering relies on branch reach assumptions

## Step 1 -- Structured IF core

Implemented the first lowering path for `IF / ELSE / ENDIF`.

## Step 2 -- Structured IF nesting and ELSEIF

Implemented nested structured `IF` lowering with `ELSEIF`.

## Step 3 -- Structured DO lowering

Implemented `DO / DOEXIT / ITERATE / ENDDO` lowering.

## Step 4 -- Branch-range hardening

Audit structured control-flow lowering for branch distance limits and add
long-range-safe emission patterns where short `bra`/`brt`/`brf` targets may
overflow.

**Deliverable**: branch-range-safe structured IF and DO lowering.

**Test**: demos and regressions that force larger emitted blocks while still
producing correct control flow.

## Step 5 -- Structured SELECT lowering

Implement `SELECT / WHEN / OTHERWISE / ENDSEL` using the hardened structured
control-flow emission model.

**Deliverable**: select/when parser and lowering path.

**Test**: a demo and regression proving multi-arm dispatch and default-arm
behavior.

## Step 6 -- Integration pass

Run an integration pass across the structured families together and tighten docs
and demos around the now-supported subset.

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
