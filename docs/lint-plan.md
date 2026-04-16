# cor24lint Saga Plan

## Overview

Build `cor24lint`, a Rust-based static analysis tool for COR24 assembly.
Consumes the assembler's IR (shared parser with `cor24-run`).

## Pre-requisites

- COR24 assembler parser/IR extracted from `cor24-rs` into a shared crate
- IR node type with source location, opcode, operands, provenance
- Basic test harness that loads a `.s` file and produces an IR

## Saga: Phase A -- Parser/IR and Tier 1 Rules

### Step 1: Extract shared parser crate

Extract the assembler's lexer and parser from `cor24-rs/src/assembler.rs`
into a new crate `cor24-ir` (or `cor24-parse`) that:
- Produces an IR with source locations
- Exposes `ParseError` with line/column
- Can be consumed by both `cor24-run`'s assembler and `cor24lint`

**Deliverable**: `cor24-ir` crate with `parse()` -> `Vec<IrNode>` API.
**Test**: existing `cor24-run` tests pass using the new crate.

### Step 2: cor24lint skeleton

Create `sw-cor24-lint/` with:
- `Cargo.toml` depending on `cor24-ir`
- CLI entry point: `cor24lint <file.s> [options]`
- Load file, parse to IR, print "N instructions, 0 warnings"
- `--profile` flag (strict-human, strict-codegen, compat)

**Deliverable**: `cargo run -- ../test.s` produces summary output.
**Test**: zero warnings on a valid input file.

### Step 3: `cor24-branch-range` rule

Check all `bra`/`brt`/`brf` instructions.  Compute the byte offset to the
target label.  Flag if offset exceeds the ±127 byte architectural limit.

This rule exists partly because the assembler already catches it, but
cor24lint provides richer diagnostics and can suggest the long-form fix.

**Deliverable**: `cor24-branch-range` rule fires on out-of-range branches.
**Test**: regression test with a file containing a branch-too-far pattern.

### Step 4: `cor24-branch-relay` rule

Build CFG.  Detect blocks whose only instruction is an unconditional
transfer to another block.  Flag as relay.  Suggest `la` + `jmp` long form.

**Deliverable**: CFG builder + relay detection.
**Test**: detect relay chains in hand-crafted and agent-generated code.

### Step 5: `cor24-frame-arg-offset` rule

For each function (identified by label + frame setup pattern), determine
the frame size from the prologue push sequence.  Check all `lw`/`sw`
with `(fp)` base that the offset is within the frame.

**Deliverable**: frame size inference + offset validation.
**Test**: detect the `9(fp)` vs `6(fp)` bug pattern.

### Step 6: `cor24-push-pop-imbalance` rule

For each basic block, count `push` and `pop` instructions.  Flag if
they don't balance (net push/pop != 0 at block exit, accounting for
calls and returns).

**Deliverable**: push/pop counter per block.
**Test**: detect the `push r0; jal; add sp,3; ...; pop r0` double-pop bug.

### Step 7: `cor24-call-clobber` rule

Track register liveness at `jal` call sites.  Flag if a register
holding a needed value is not saved before the call and the callee
doesn't preserve it.

**Deliverable**: lightweight liveness analysis around call sites.
**Test**: detect r1 buffer-pointer clobber pattern.

### Step 8: `cor24-return-clobber` and `cor24-saved-reg-overwrite`

Check return sequences.  Flag if a local variable stored in a
frame slot overwrites a saved register that the return sequence
needs (e.g., `sw r1, 6(fp)` in a frame where `6(fp)` is saved r1).

**Deliverable**: frame slot vs saved-register conflict detection.
**Test**: detect the `sw buf_ptr, 6(fp)` overwriting saved-r1 bug.

### Step 9: Tier 1 integration and profiles

Wire all Tier 1 rules into the rule engine.  Implement profile
selection.  Ensure `strict-human` defaults to deny, `compat` to warn.

**Deliverable**: working Tier 1 lint pass with profile support.
**Test**: `cor24lint --profile strict-human` errors on all Tier 1 patterns.

## Saga: Phase B -- Tier 2 Idiom Rules

### Step 10: `cor24-manual-zero` rule

Detect `la r0, 0` (or any `la rX, 0`).  Suggest using Z register
directly in comparisons: `ceq r0, z` instead of `la r1, 0; ceq r0, r1`.

### Step 11: `cor24-noncanonical-cmp` and `cor24-noncanonical-cond`

Check compare/branch sequences against the COR24 canonical patterns.
Flag non-canonical condition setup (e.g., `clu` where `ceq` with Z
would suffice).

### Step 12: `cor24-jump-to-jump` and `cor24-temp-move`

Detect blocks that are pure forwarding jumps.  Detect unnecessary
register moves where the source is already in the destination or
where Z suffices.

### Step 13: `cor24-double-jal` rule

Detect consecutive `jal` instructions without an intervening save of
the first return address.

## Saga: Phase C -- Tier 3 Style and Cross-Reference

### Step 14: Label naming conventions

Check label names against configurable regex patterns.  Default:
local labels `_L` prefix, routine labels lowercase-snake_case.

### Step 15: Prologue/epilogue consistency

Within a profile, check that all functions use the same prologue shape
(push fp, push r1, ...) and epilogue shape (mov sp,fp; pop...).

### Step 16: Cross-reference report

Emit label definition/reference summary.  Per-routine register usage.
Call graph.  Macro expansion origin tracking.

### Step 17: JSON output format

Machine-readable output for `strict-codegen` profile.  Enables
integration with editors, CI, and agent feedback loops.

## Saga: Phase D -- Integration

### Step 18: CI integration

Add `cor24lint` to CI pipeline.  Fail on `deny` rules in
`strict-human` profile.  Warn-only in other profiles.

### Step 19: Editor support

LSP or at least `--format json` for editor integration.  Suggest fixes
for auto-correctable rules (branch relay -> la+jmp).

### Step 20: HLASM macro-aware lint

When linting HLASM-generated output, track macro expansion boundaries.
Attribute warnings to the originating macro.  Detect non-canonical
prologues emitted by macro expansion.
