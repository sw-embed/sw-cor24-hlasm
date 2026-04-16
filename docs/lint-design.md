# COR24 Assembler Linter Design

## Overview

A static analysis tool for COR24 assembly code, both hand-written and
generated (by HLASM, PL/SW, compiler backends).  Built in Rust, consuming
the assembler's IR.

**Name**: `cor24lint`

**Design philosophy**: HLASM-style structural analysis +
NASM-style configurable warning classes + COR24-specific idiom rules.

## Architecture

```
  .s / .hlasm source
        |
        v
  +------------------+
  | cor24-assembler  |  (shared parser/IR with cor24-run's assembler)
  |   lexer          |
  |   parser         |
  |   IR builder     |
  +------------------+
        |
        v
  +------------------+
  | cor24lint        |
  |   IR consumer    |
  |   CFG builder    |
  |   rule engine    |
  |   reporter       |
  +------------------+
        |
        v
  warnings / errors / reports
```

### Assembly IR

Rich intermediate representation, not just tokens.  Each IR node carries:

- source file, line, column
- labels (defined and referenced)
- instruction opcode and operand registers/immediates
- resolved branch type (short, long)
- macro-expansion provenance (when available)
- section / location counter

### Analysis Passes

1. **CFG construction** -- basic blocks, fallthrough edges, conditional
   edges, call edges, return exits, unreachable blocks.
2. **Light dataflow** -- track which register holds the active compare/test
   result, zero-known values, Z-derived values.
3. **Symbol resolution** -- label definitions, references, scope.
4. **Macro origin tracking** -- which macro expanded each instruction.

## Rule System

NASM-style warning classes.  Each rule has:

- **Rule ID**: `cor24-<category>-<name>` (e.g. `cor24-branch-relay`)
- **Default severity**: `allow`, `warn`, `deny`
- **Profile membership**: which profiles enable it
- **Suppression scope**: file, function, line

### Profiles

| Profile | Target | Idiom checks | Style | Structural | Output |
|---------|--------|-------------|-------|------------|--------|
| `strict-human` | Handwritten asm | Aggressive | On | On | Human-readable |
| `strict-codegen` | HLASM/PL/SW/compiler output | Structural only | Off | On | JSON + human |
| `compat` | Legacy code | Major only | Off | Basic | Human-readable |

### Rule Catalog

#### Tier 1: correctness (default: deny / error)

| Rule ID | Description |
|---------|-------------|
| `cor24-branch-range` | Short branch target out of architectural range |
| `cor24-branch-relay` | Relay chain used where long-range jump exists |
| `cor24-cmp-branch-mismatch` | Compare/branch sequence cannot work under COR24 condition semantics |
| `cor29-unreachable` | Unreachable code after unconditional transfer (no label target) |
| `cor24-frame-arg-offset` | Frame-relative load/store uses wrong offset for frame size |
| `cor24-push-pop-imbalance` | Push/pop count mismatch in a basic block |
| `cor24-return-clobber` | Return sequence clobbers register needed by caller |
| `cor24-saved-reg-overwrite` | Local variable stored in saved-register frame slot |

#### Tier 2: idiom (default: warn)

| Rule ID | Description |
|---------|-------------|
| `cor24-branch-relay` | Relay branches instead of `la` + `jmp` long form |
| `cor24-jump-to-jump` | Block whose only instruction is another unconditional jump |
| `cor24-manual-zero` | `la r0, 0` instead of using Z register |
| `cor24-noncanonical-cmp` | Non-canonical compare against zero |
| `cor24-noncanonical-cond` | Non-canonical condition setup before conditional branch |
| `cor24-temp-move` | Pointless move through temp register when Z or direct form suffices |
| `cor24-call-clobber` | Value in register destroyed by `jal` without save/restore |
| `cor24-double-jal` | Two consecutive `jal` without saving first return address |

#### Tier 3: style (default: allow, warn in strict-human)

| Rule ID | Description |
|---------|-------------|
| `cor24-label-naming` | Label naming conventions |
| `cor24-prologue-shape` | Consistent push/mov-fp sequence |
| `cor24-epilogue-shape` | Consistent mov-sp/pop/jmp sequence |
| `cor24-comment-tricky` | Missing comment on hand-coded tricky sequences |
| `cor24-leaf-no-save` | Leaf function saves registers unnecessarily |

### Specific Rules in Detail

#### `cor24-branch-relay`

Trigger: block A conditionally branches to block B, where B contains only
an unconditional short-range transfer to C, and A->C could use a canonical
long-range control transfer.

```
warning: suspicious branch relay: short-range branch uses relay label
        _L123 to reach distant target _foo.  Prefer la r1, _foo; jmp (r1).
  --> src/foo.s:42:5
   |
42 |     bra _L123
   |     ^^^^^^^^ help: replace with la r1, _foo; jmp (r1)
```

#### `cor24-frame-arg-offset`

Trigger: `lw` or `sw` uses offset N(fp) where N does not match the
function's frame size.  E.g., a 2-register frame (push fp, r1 = 6 bytes)
using `9(fp)` for the arg (should be `6(fp)`).

```
error: frame arg offset mismatch: function has 2-register frame (6 bytes)
       but loads arg from 9(fp) instead of 6(fp)
  --> src/foo.s:37:5
   |
37 |     lw r1, 9(fp)
   |         ^^^^^^^
```

#### `cor24-call-clobber`

Trigger: register R holds a value needed after `jal r1, (r0)` but
the callee may modify R (not in its save set or no save/restore around
the call site).

```
warning: value in r1 destroyed by jal without save/restore
  --> src/foo.s:55:5
   |
55 |     jal r1, (r0)
   |     ^^^^^^^^^^^^ r1 held buffer pointer before this call
```

## Reports

### Cross-reference report

Per-routine summary:

- Labels defined / referenced
- Register usage (which regs are read/written)
- Macro expansions by source site
- Branch density / call graph

### Flow report

Per-routine CFG summary:

- Basic blocks, edges
- Relay blocks detected
- Dead blocks
- Return sites
- Abnormal exits

### Idiom report

- Non-canonical compare/branch sequences
- Non-canonical zero usage
- Special-register usage summary

## Implementation Plan

See `docs/lint-plan.md` for the phased saga plan.

## References

- NASM warning classes: `-w+/-w-` per-warning control
- GNU as branch relaxation / trampoline insertion
- IBM HLASM Toolkit: Cross-Reference Facility, Program Understanding Tool
- Clippy rule architecture: rule IDs, severities, lint levels
