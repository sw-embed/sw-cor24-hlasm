# HLASM Macro-Assembler Demos

Each demo is a self-contained `.hlasm` source file showing one or more features.
Use `make_bin.sh` to convert `.hlasm` to `.bin` for loading into the emulator.

## Feature Status

| Demo | Feature | Status |
|------|---------|--------|
| d01 | Basic passthrough | WORKS |
| d02 | Simple macro (no params) | WORKS |
| d03 | Macro with parameters | BUG: params not substituted |
| d04 | SET / IFDEF / ENDIFASM | WORKS |
| d05 | IFEQ / IFNE comparison | WORKS |
| d06 | ELSEASM toggle | WORKS |
| d07 | Nested conditionals | WORKS |
| d08 | Macros + conditionals | WORKS |
| d09 | Comments (; and #) | WORKS (pass through) |
| d10 | Multiple macros | BUG: second overwrites first |
| d11 | IF/ELSEIF/ELSE/ENDIF | NOT IMPLEMENTED |
| d12 | DO/DOEXIT/ENDDO loops | NOT IMPLEMENTED |
| d13 | SELECT/WHEN/ENDSEL | NOT IMPLEMENTED |
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

```
MACRO name
 <body>
MEND
<name>              ; invoke macro
```

```
MACRO name param1,param2
 push \param1
 push \param2
MEND
<name> r0,r1        ; invoke with arguments
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

### Structured Control Flow (NOT YET IMPLEMENTED)

#### IF / ELSEIF / ELSE / ENDIF
```
IF cc_eq, r0, 0
    add r1,1
ELSEIF cc_lt, r1, 10
    add r2,1
ELSE
    add r3,1
ENDIF
```
Condition codes: cc_eq, cc_ne, cc_lt (signed), cc_lu (unsigned),
cc_zset (C flag set), cc_zclr (C flag clear).

#### DO / DOEXIT / ENDDO
```
DO
    add r0,1
    DOEXIT cc_eq, r0, 10
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
