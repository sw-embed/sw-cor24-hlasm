# HLASM Macro-Assembler Demos

Each demo is a self-contained `.hlasm` source file showing one or more features.
Use `make_bin.sh` to convert `.hlasm` to `.bin` for loading into the emulator.

## Feature Status

| Demo | Feature | Status |
|------|---------|--------|
| d01 | Basic passthrough | WORKS |
| d02 | Simple macro (no params) | WORKS |
| d03 | HLASM-style named macro parameters | WORKS |
| d04 | SET / IFDEF / ENDIFASM | WORKS |
| d05 | IFEQ / IFNE comparison | WORKS |
| d06 | ELSEASM toggle | WORKS |
| d07 | Nested conditionals | WORKS |
| d08 | Macros + conditionals | WORKS |
| d09 | Comments (; and #) | WORKS (pass through) |
| d10 | Multiple macros | WORKS |
| d11 | IF/ELSEIF/ELSE/ENDIF | WORKS |
| d12 | DO/DOEXIT/ENDDO loops | WORKS |
| d13 | SELECT/WHEN/ENDSEL | WORKS |
| d14 | IFNDEF (not defined) | WORKS |
| d15 | Realistic program | WORKS |
| d16 | Bootstrap `hlasm0` subset | WORKS |
| d17 | Multi-buffer source input | WORKS |
| d18 | Include-ready multi-buffer chain | WORKS |
| d19 | Bootstrap memory map proof | WORKS |
| d20 | Patchable main source window | WORKS |
| d21 | Directive-driven source switch | WORKS |
| d22 | Include-return source stack | WORKS |
| d23 | Named include table | WORKS |
| d24 | Nested named includes | WORKS |
| d25 | Split bootstrap sourceset proof | WORKS |
| d26 | Structured branch-range hardening | WORKS |
| d27 | Positional macro parameters | WORKS |
| d28 | Macro robustness stress | WORKS |
| d29 | Control-flow integration proof | WORKS |
| d30 | Structured annotation comments | WORKS |
| d31 | Large source + macro capacity | WORKS |
| d32 | Literals and data ergonomics | WORKS |
| d33 | Symbols and expressions | WORKS |

## Demo Policy

Every new HLASM feature or bootstrap milestone should add:

- one source demo
- one `reg-rs` regression test
- one README status entry

## Running a Demo

```bash
# Convert source to binary
bash demos/make_bin.sh demos/d01_passthrough.hlasm demos/d01_passthrough.bin

# Run on emulator
cor24-run --run hlasm.s --load-binary demos/d01_passthrough.bin@524288 --speed 0 -n 100000 2>&1
```

## HLASM Syntax Reference

### Macros

Current supported baseline:

- `MACRO name` starts a definition and `MEND` ends it
- definition lines are consumed by the assembler and are not emitted to output
- simple no-parameter invocations expand stably
- positional parameters `&1`, `&2`, ... expand stably
- HLASM-style named parameters `&name` in both the definition header and body
  expand stably
- macro names up to 31 characters are supported
- multi-macro/local-label robustness is not complete yet
- macro bodies are plain text expansion; conditional-assembly directives and
  structured control-flow keywords are supported as top-level source forms,
  not as reparsed directives nested inside macro bodies

```
MACRO name
 <body>
MEND
<name>              ; invoke macro
```

This repo is aiming toward HLASM-like behavior on the MVS lineage, but the
currently implemented macro subset is still narrower than full HLASM macro
semantics.

Named parameters:
```
MACRO PUSH2 &LEFT,&RIGHT
 push &LEFT
 push &RIGHT
MEND
PUSH2 r0,r1
```

Positional parameters:
```
MACRO PUSH2
 push &1
 push &2
MEND
PUSH2 r0,r1
```

### Conditional Assembly (SET / IFDEF / IFNDEF / IFEQ / IFNE / ELSEASM / ENDIFASM)

```
SET DEBUG,1         ; define symbol DEBUG = 1

IFDEF DEBUG         ; include if DEBUG is defined
 nop
ENDIFASM

IFNDEF RELEASE      ; include if RELEASE is NOT defined
 nop
ENDIFASM

IFEQ VER,3          ; include if VER equals 3
 nop
ELSEASM             ; otherwise include this block
 add r0,1
ENDIFASM

IFNE VER,2          ; include if VER does NOT equal 2
 sub r0,1
ENDIFASM
```

Assembly-time numeric literals accepted by `SET`, `IFEQ`, `IFNE`, and
structured compare lowering:
```
SET COUNT,42
SET MASK,0x2A
SET BITS,0b101010
SET SAME,2Ah
```

Small assembly-time symbol arithmetic is also supported for `SET`, `EQU`,
`IFEQ`, and `IFNE`:
```
MASK EQU 0x20
STEP EQU 2
SET BASE,8
SET TOTL,MASK+BASE+STEP
IFEQ TOTL,42
 nop
ENDIFASM
```

Current-location and label arithmetic remain assembler passthrough, not
assembly-time evaluation inside `hlasm`:
```
mark:
 .word mark+3
 .word tail-mark
tail:
```

### Data Directives

Current practical data-directive conveniences:

- `.ascii "text"` lowers to a `.byte` list
- `.asciz "text"` lowers to a `.byte` list with trailing `0`
- `.space N` lowers to `N` zero bytes
- `.fill N,V` lowers to `N` copies of byte value `V`

Examples:
```
.ascii "HI\n"
.asciz "OK"
.space 4
.fill 3,0x7F
```

### Source Buffer Control

```
SRCBUF 1            ; jump directly to preloaded source slot 1

INCBUF 1            ; push current slot/position, read slot 1, then
                    ; return to the caller source when slot 1 hits EOF

INCLUDE tail        ; resolve "tail" through the low-SRAM include-name table,
                    ; then include that slot and resume the caller source
```

Bootstrap-facing include demos and proofs now use a source-set manifest:
optional `PROFILE file`, then `ROOT dir`, optional `MAINADDR` / `EXTRAADDR` /
`ALIGN`, `SOURCESET child.sourceset`, then `MAIN file.hlasm` plus repeated
`INCLUDE name file.hlasm`. The host-side runner builds the `.bin` files, packs
include buffers from their real sizes, emits the unchanged low-SRAM config
image, and feeds the same runtime include table into `hlasm.s`.

Demo 24 now uses that composed source-set path directly, so the fragment model
is exercised on a named-include proof as well as the split `hlasm0` bootstrap
proof.

Demo 23 now uses the same composed source-set path, so both named-include
proofs run through the shared demo profile and fragment workflow.

Conditionals can nest:
```
SET OUTER,1
SET INNER,0
IFDEF OUTER
 IFDEF INNER
  add r0,1
 ELSEASM
  nop
 ENDIFASM
ELSEASM
 sub r0,1
ENDIFASM
```

### Structured Control Flow

#### IF / ELSEIF / ELSE / ENDIF
Nested `IF` blocks and `ELSEIF` chains now lower to plain labels and branches.
Structured conditionals are emitted in a long-range-safe form: a short
reversed conditional branch skips over an unconditional `jmp`, so generated
control flow does not depend on raw `bra` reach.
When `SET HLANN,1` is active, `hlasm` also emits opt-in semicolon comment
lines that mark structured source boundaries in the lowered `.s` output.

```
IF cc_eq, r0, 0
    add r1,1
    IF cc_ne, r1, z
        sub r0,r0
    ELSEIF cc_lt, r2, 10
        add r2,1
    ELSE
        nop
    ENDIF
ELSEIF cc_zclr
    add r0,1
ELSE
    add r2,2
ENDIF
```
Condition codes: cc_eq, cc_ne, cc_lt (signed), cc_lu (unsigned),
cc_zset (C flag set), cc_zclr (C flag clear).

Annotation example:
```
SET HLANN,1
IF cc_eq, r0, 0
    add r1,1
ENDIF
```

This emits normal lowered assembly plus comment markers such as:
```
; HLASM IF cc_eq, r0, 0
; HLASM THEN
; HLASM ENDIF
```

#### DO / DOEXIT / ITERATE / ENDDO
Loop lowering uses the same long-range-safe pattern for generated exits and
back-edges, with unconditional structured transfers emitted as `jmp`.

```
DO
    add r0,1
    DOEXIT cc_eq, r0, 10
    bra _body
ENDDO
DO
    add r1,1
    ITERATE
ENDDO
```

#### SELECT / WHEN / OTHERWISE / ENDSEL
```
SELECT r0
    WHEN 0
        add r1,1
    WHEN 1
        add r2,1
    OTHERWISE
        add r3,1
ENDSEL
```

### Passthrough

Any line that is not a directive, macro definition, or structured keyword
is emitted unchanged. This includes labels, instructions, and comment lines.

### Labels
```
mylabel:
 bra mylabel
```
