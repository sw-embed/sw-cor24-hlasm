# Design Document

## Syntax Design

### Input

.hlasm source text loaded into memory at a fixed address via `--load-binary`.
The macro-assembler reads characters from this buffer and writes expanded
assembly to UART.

### Source Format

Lines are newline-terminated (0x0A). The macro-assembler processes source
line by line, recognizing:

- **Keywords**: MACRO, MEND, IF, ELSEIF, ELSE, ENDIF, DO, DOEXIT, ITERATE,
  ENDDO, SELECT, WHEN, OTHERWISE, ENDSEL, SET, IFDEF, IFNDEF, IFEQ, IFNE,
  ELSEASM, ENDIFASM
- **Labels**: name followed by colon on own line
- **Instructions**: standard COR24 mnemonics
- **Comments**: semicolon or hash to end of line
- **Directives**: `.byte`, `.word`, `.comm`, `.org` (passed through),
  `.ascii`, `.asciz`, `.space`, `.fill` (lowered to `.byte` lists)
- **Numeric literals**: decimal plus `0x` hex, `0b` binary, and `h`/`H`
  hex suffix forms for assembly-time parsing
- **Small assembly-time expressions**: `SET`, `EQU`, `IFEQ`, and `IFNE`
  accept literals and known symbols joined by `+` and `-`
- **Source libraries**: named `COPY` and `INCLUDE` members can be supplied by
  the host-side source-set runner and consumed from assembler-facing source
- **Opt-in listing comments**: `SET HLIST,1` emits grep-friendly semicolon
  comments for copied members, macro definitions, macro expansion, and selected
  consumed directives
- **Opt-in xref report**: `SET HLXREF,1` emits a compact end-of-run cross-
  reference section for copied members, macro definitions, macro expansion
  counts, and assembly-time symbols seen through `SET`/`EQU`
- **Opt-in diagnostic channel**: `SET HLDIAG,1` activates a central warn
  routine that emits `; !! hlasm: <msg> at src<id>:<line>` lines into the
  generated stream, keyed to a per-source line counter updated by the read
  path. The baseline step emits a single end-of-run banner as smoke; later
  steps wire real callers

### Structured Control-Flow Syntax

#### IF / ELSEIF / ELSE / ENDIF

```
IF cc_eq, r0, 0
    ; body when r0 == 0
ELSEIF cc_lt, r1, 10
    ; body when r0 != 0 and r1 < 10
ELSE
    ; body otherwise
ENDIF
```

Condition specifiers: `cc_eq`, `cc_ne`, `cc_lt` (signed), `cc_lu` (unsigned),
`cc_zset` (C flag set), `cc_zclr` (C flag clear).

Lowering produces labels and branches:
```
    ceq r0, z
    brf .L0001
    ; IF body
    bra .L0002
.L0001:
    ; ELSEIF/ELSE body
.L0002:
```

#### DO / DOEXIT / ITERATE / ENDDO

```
DO
    ; body (infinite loop)
    DOEXIT cc_eq, r0, 0
    ; more body
ENDDO
```

Lowering:
```
.L0001:
    ; body
    ceq r0, z
    brt .L0002
    ; more body
    bra .L0001
.L0002:
```

#### SELECT / WHEN / OTHERWISE / ENDSEL

```
SELECT r0
    WHEN 0
        ; case 0
    WHEN 1
        ; case 1
    OTHERWISE
        ; default
ENDSEL
```

Lowering produces a compare-and-branch chain.

### Macro Syntax

Current baseline:

- `MACRO name` ... `MEND` definitions are recognized and suppressed from output
- simple invocations expand by macro name lookup at the start of the line
- positional parameters `&1`, `&2`, ... expand
- HLASM-style named parameters `&name` in the definition header and body
  expand
- macro names up to 31 characters are supported
- repeated macro invocation and `\@` local-label expansion are stable across
  multiple macro definitions
- local-label behavior is still a partial subset, not full HLASM compatibility
- macro bodies expand directly to plain output lines; conditional assembly and
  structured IF/DO/SELECT are currently supported as source-level forms rather
  than directives re-evaluated from inside macro bodies

Near-term compatibility target:

- move toward IBM HLASM-like behavior on the MVS lineage
- keep the currently supported syntax documented explicitly until the fuller
  parameter and local-label model is implemented

```
MACRO PUSHREG
    push r0
MEND
```

Invocation:
```
    PUSHREG
    PUSHREG
```

Named parameters:
```
MACRO PUSH2 &LEFT,&RIGHT
    push &LEFT
    push &RIGHT
MEND
```

Positional parameters:
```
MACRO PUSH2
    push &1
    push &2
MEND
```

### Conditional Assembly

```
SET DEBUG, 1
SET VERSION, 3
MASK EQU 0x20
SET TOTAL, MASK+10

IFDEF DEBUG
    ; debug-only code
ENDIF

IFEQ VERSION, 3
    ; version 3 specific code
ELSEASM
    ; other versions
ENDIFASM

IFNE TOTAL, 41
    ; expression-based guard
ENDIFASM
```

### Passthrough

Any line that is not a macro definition, structured block, conditional, or
keyword is passed through to output unchanged (plain COR24 assembly).
That includes ordinary assembler expressions such as `label+3` and `end-start`,
which are preserved for the downstream assembler rather than evaluated by
`hlasm` itself.

### Source Library Workflow

`COPY name` is an HLASM-style alias for named source inclusion. In the current
workflow, host-side source sets provide named members:

```
COPY libmac
COPY libsym
```

using source-set entries like:

```
COPY libmac macros.hlasm
COPY libsym symbols.hlasm
```

This reuses the same runtime named-include table as `INCLUDE`, but gives macro
and symbol libraries an explicit source-oriented entry point.

### Listing / Xref Comments

`SET HLIST,1` enables compact listing/xref-friendly comments in the lowered
output, for example:

```
; HLASM COPY libmac
; HLASM MACRO PUSH2
; HLASM EXPAND PUSH2
```

This is meant to make generated `.s` files easier to inspect with normal text
tools. `SET HLANN,1` remains the separate switch for structured-control-flow
source markers; users can enable either or both.

`SET HLXREF,1` enables a compact end-of-run xref report, for example:

```
; HLASM XREF BEGIN
; HLASM XREF COPY libmac
; HLASM XREF MACRO PUSH2
; HLASM XREF EXPAND PUSH2 1
; HLASM XREF SYMBOL LOCAL
; HLASM XREF END
```

`HLIST` and `HLXREF` are complementary: `HLIST` annotates the lowered stream
as it is emitted, while `HLXREF` adds a summary section at the end.

## Label Generation

- Global labels: passed through as-is
- Macro-local labels: `\@` becomes unique counter (e.g., `loop0001`)
- Structured block labels: `.L<counter>` (e.g., `.L0001`, `.L0002`)
- Counter is global, monotonically increasing

## Condition Specifier Semantics

| Specifier | COR24 Instructions | Semantics |
|-----------|-------------------|-----------|
| `cc_eq` | `ceq ra, rb` | C set if ra == rb |
| `cc_ne` | `ceq ra, rb` | C clear if ra != rb |
| `cc_lt` | `cls ra, rb` | C set if ra < rb (signed) |
| `cc_lu` | `clu ra, rb` | C set if ra < rb (unsigned) |
| `cc_zset` | (no compare) | C flag already set |
| `cc_zclr` | (no compare) | C flag already clear |

For constant comparisons, load constant into a register first:
- 0..127: `lc r_tmp, const`
- 0..255: `lcu r_tmp, const`
- larger: `la r_tmp, const`

## Register Allocation

| Register | Use |
|----------|-----|
| r0 | Work register / scratch |
| r1 | Return address / subroutine link |
| r2 | Current pointer / working area |
| fp | Frame pointer for subroutines |
| sp | Data stack (hardware push/pop) |

## Subroutine Convention

Follows the pattern from sw-cor24-forth and sw-cor24-rpg-ii:
- Caller pushes arguments right-to-left on stack
- Callee: push fp, push r2, push r1, mov fp,sp
- Return value in r0
- Callee restores: mov sp,fp, pop r1, pop r2, pop fp, jmp (r1)

## Data Structures

### Macro Table Entry

Fixed-size records in memory:
- Name (up to 16 chars, null-terminated)
- Param count (1 byte)
- Param names (up to 8 params, 8 chars each)
- Default values (up to 8, 24-bit integers)
- Body pointer (offset into source buffer)
- Body length (24-bit)

### Symbol Table Entry

- Name (up to 16 chars)
- Value (24-bit integer for SET symbols)
- Type flag: SET, LABEL, MACRO

### Token

Minimal token representation:
- Type (1 byte): KEYWORD, MNEMONIC, REGISTER, NUMBER, STRING, LABEL, IDENT, COMMENT, COMMA, LPAREN, RPAREN, NEWLINE, EOF
- Value (up to 8 bytes for the token text or numeric value)

## Character I/O

UART at 0xFF0100 (data) and 0xFF0101 (status):
- TX busy: bit 7 of status register (sign-extended, negative = busy)
- RX ready: bit 0 of status register

## Testing Approach

Tests use reg-rs golden-output regression testing:
- Test prefix: `hlasm_`
- Input source prepared as binary file, loaded via `--load-binary`
- Output captured via UART
- Preprocess filter extracts UART output
- Test files in `reg-rs/` directory with `.rgt` and `.out` pairs
