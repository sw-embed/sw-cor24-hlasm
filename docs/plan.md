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

The next active saga is focused on the missing structured control-flow layer:

- `IF / ELSEIF / ELSE / ENDIF`
- `DO / DOEXIT / ITERATE / ENDDO`
- `SELECT / WHEN / OTHERWISE / ENDSEL`

## Approach

Keep `hlasm.s` target-native and incremental.

- preserve the existing UART-output model
- preserve the existing bootstrap input/config path
- add one structured family at a time, each with a demo, a `reg-rs` proof, and
  a docs update
- prefer lowering to plain labels and branches rather than introducing a second
  output format

## Step 1 -- Structured IF core

Implement the first lowering path for `IF / ELSE / ENDIF`.
Start with a minimal condition grammar that matches the design docs and lower
blocks into plain labels plus branch instructions.

**Deliverable**: parser/lowering path for single-level `IF / ELSE / ENDIF`.

**Test**: a demo and regression proving both taken and skipped branches emit
the expected plain `.s` output.

## Step 2 -- Structured IF nesting and ELSEIF

Extend the structured-IF path to support nesting and `ELSEIF`.
Make label generation and block-stack handling robust enough for realistic
control-flow trees.

**Deliverable**: nested `IF` lowering with `ELSEIF`.

**Test**: a demo and regression covering nested branches and at least one
multi-arm `ELSEIF` chain.

## Step 3 -- Structured DO lowering

Implement `DO / DOEXIT / ITERATE / ENDDO`.
Lower loops into explicit top/bottom labels with branch exits and iteration
paths.

**Deliverable**: loop parser/lowering path with stack tracking for nested loops.

**Test**: a demo and regression covering loop body emission, early exit, and
iterate-to-top behavior.

## Step 4 -- Structured SELECT lowering

Implement `SELECT / WHEN / OTHERWISE / ENDSEL`.
Lower dispatch chains into explicit compare-and-branch sequences.

**Deliverable**: select/when parser and lowering path.

**Test**: a demo and regression proving multi-arm dispatch and default-arm
behavior.

## Step 5 -- Integration pass

Run the structured families together in a larger proof source and tighten docs
and demos around the now-supported control-flow subset.

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
