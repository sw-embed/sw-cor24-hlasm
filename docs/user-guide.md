# hlasm User Guide

hlasm is a macro assembler for the COR24 24-bit RISC CPU, modelled on IBM's
High Level Assembler (HLASM). You write `.hlasm` source with macros, named
constants, expressions, conditional assembly and structured control flow
(IF / DO / SELECT); hlasm turns it into plain COR24 assembly (`.s`) that
`cor24-asm` assembles and `cor24-emu` (or the FPGA) runs.

hlasm is itself a COR24 program (`hlasm.s`), so it runs on the emulator
like any other COR24 code: the source is loaded into memory and the
generated assembly comes out of the UART.

Every example in this guide was run through hlasm; the outputs shown are
what it printed.

- [Why use hlasm](#why-use-hlasm)
- [Setup](#setup)
- [Running hlasm](#running-hlasm)
- [Source format](#source-format)
- [Named constants: EQU and SET](#named-constants-equ-and-set)
- [Expressions](#expressions)
- [Macros](#macros)
- [Conditional assembly](#conditional-assembly)
- [Structured control flow](#structured-control-flow)
- [Data directives](#data-directives)
- [Multiple source files: INCLUDE and COPY](#multiple-source-files-include-and-copy)
- [Listings, cross-reference and diagnostics](#listings-cross-reference-and-diagnostics)
- [Limits and error messages](#limits-and-error-messages)
- [Not supported yet](#not-supported-yet)
- [Further reading](#further-reading)

## Why use hlasm

Plain COR24 assembly makes you do by hand what a macro assembler does for
you:

- **No named constants.** `cor24-asm` has no `EQU`, so every UART address,
  buffer size and character code is a bare number repeated wherever it is
  used. hlasm's `EQU` and expressions (`SIZE EQU WORDS*3`) are computed at
  assembly time and written into the output as numbers.
- **Repeated idioms.** Polling the UART, saving registers or setting up a
  call frame is the same 4-6 lines every time. A macro writes it once;
  `\@` gives each expansion its own labels, so loops inside macros work.
- **Branch spaghetti.** Hand-written `if`/`else` and loops need invented
  labels and inverted conditions. `IF`/`ELSE`/`ENDIF`, `DO`/`DOEXIT`/`ENDDO`
  and `SELECT`/`WHEN` read like the logic and generate the labels for you.
  COR24 branches only reach -128..127 bytes; hlasm measures its output and
  switches to a long-range jump automatically when a block is too big, so
  structured code never fails with "branch target too far".
- **One source, several builds.** `SET`/`IFDEF`/`IFEQ` select debug code,
  targets or features without editing the source.
- **Readable output.** The generated `.s` is ordinary COR24 assembly you can
  read, diff and debug; optional annotations mark where each structured
  statement came from.

A small example: print "Hi" on the UART.

```
; hello.hlasm: print "Hi" on the UART, then spin
UART EQU -65280

MACRO PUTC &CH
 lc r0,&CH
L\@:
 lb r1,1(r2)
 cls r1,z
 brt L\@
 sb r0,0(r2)
MEND

 la r2,UART
 PUTC 'H'
 PUTC 'i'
halt:
 bra halt
```

hlasm output (blank lines from the consumed `EQU`/`MACRO` lines trimmed):

```
; hello.hlasm: print "Hi" on the UART, then spin
 la r2,-65280
 lc r0,72
L0001:
 lb r1,1(r2)
 cls r1,z
 brt L0001
 sb r0,0(r2)
 lc r0,105
L0002:
 lb r1,1(r2)
 cls r1,z
 brt L0002
 sb r0,0(r2)
halt:
 bra halt
```

Assembled with `cor24-asm` and run on `cor24-emu`, it prints `Hi`. Each
further character is one line of source instead of six, and the UART
address and character codes are names instead of numbers.

## Setup

You need three tools; hlasm itself needs no build step.

| Tool | From | Used for |
|---|---|---|
| `cor24-asm` | [sw-cor24-x-assembler](https://github.com/sw-embed/sw-cor24-x-assembler) | assembling `hlasm.s` and hlasm's output |
| `cor24-emu` | [sw-cor24-emulator](https://github.com/sw-embed/sw-cor24-emulator) | running hlasm and the programs it produces |
| `reg-rs` | (test runner) | `./build.sh test` only |

`scripts/run-kernel.sh` finds `cor24-asm` and `cor24-emu` on `PATH`, through
`COR24_ASM` / `COR24_EMU`, or in sibling checkouts' `target/release`
directories (for example `../sw-cor24-x-assembler/target/release/cor24-asm`).
It assembles a `.s` file and runs it in one step; everything below uses it.

Quick checks:

```bash
./build.sh          # assemble hlasm.s (sanity check)
./demo.sh           # show a demo source, hlasm's output, and that it assembles
./build.sh test     # run the regression suite
```

## Running hlasm

hlasm reads its source from memory at address 0x080000 (524288), so a run has
three parts: turn the source into a loadable image, run hlasm on the emulator
with that image loaded, and keep the UART output.

```bash
# 1. Source text -> loadable image
bash demos/make_bin.sh prog.hlasm prog.bin

# 2. Run hlasm with the image at 0x080000; -q prints only the UART output
scripts/run-kernel.sh hlasm.s --load-binary prog.bin@524288 \
    --speed 0 -n 5000000 -q 2>/dev/null | grep -v '^Executed' > prog.s

# 3. Assemble and run the generated program
scripts/run-kernel.sh prog.s --speed 0 -n 100000
```

Notes:

- `-n` is the instruction budget for the emulator. hlasm costs roughly 10-15
  thousand instructions per source line (it makes two passes); give it
  plenty, it stops by itself when done. `--speed 0` runs at full speed.
- hlasm ends by spinning on `bra` to itself (how COR24 halts); `cor24-emu`
  detects this and stops.
- If hlasm stops with a line starting `ERROR:`, the source exceeded a limit
  or contains an error (see [Limits and error messages](#limits-and-error-messages)).
- The main source can be up to 32,767 bytes this way. Larger programs, or
  programs split into several files, use a source set
  ([INCLUDE and COPY](#multiple-source-files-include-and-copy)).

## Source format

- One statement per line, at most 256 characters.
- Lines starting with `;` are comments and are copied to the output.
- `name:` at the start of a line defines a label (passed to `cor24-asm`).
- Instructions are written as in COR24 assembly, conventionally indented by
  one space: ` add r0,1`.
- hlasm directives (`MACRO`, `SET`, `IF`, `DO`, ...) start in column 1 or
  after blanks and are upper case.
- Anything hlasm does not recognize is passed through unchanged, so any
  valid COR24 assembly is also valid hlasm source.

## Named constants: EQU and SET

```
name EQU expression
SET name,expression
```

Both define an assembly-time symbol with a 24-bit value. Names are up to 31
characters (letters, digits, `_`). `EQU` is the HLASM spelling for
constants; `SET` is used for values you redefine, such as configuration
switches.

Symbols are replaced by their values wherever a value is expected:

- operands of instructions, `.byte` and `.word`;
- compare values in `IF`, `ELSEIF`, `DOEXIT` and `WHEN`;
- `SET`, `EQU`, `IFEQ`, `IFNE`.

An operand is rewritten only if every name in it is a symbol and there is
something to compute; registers, labels and plain numbers are left for
`cor24-asm`. In a memory operand `offset(reg)` only the offset is rewritten.

```
WORDS EQU 4
SIZE EQU WORDS*3
FLAGS EQU (1<<4)|0x0F
SET LAST,SIZE-3
 lc r0,SIZE
 la r1,FLAGS
 lw r0,LAST(fp)
 lc r2,'A'+1
 .byte SIZE,FLAGS,'\n'
 .word SIZE*100
 la r0,buffer
```

Output:

```
 lc r0,12
 la r1,31
 lw r0,9(fp)
 lc r2,66
 .byte 12,31,10
 .word 1200
 la r0,buffer
```

`buffer` is a label, not a symbol, so `la r0,buffer` is left for
`cor24-asm`.

## Expressions

Expressions combine numbers, character literals and symbols:

| Precedence (high to low) | Operators |
|---|---|
| unary | `-x` `~x` `+x` |
| multiplicative | `*` `/` `%` |
| additive | `+` `-` |
| shift | `<<` `>>` |
| bitwise and | `&` |
| bitwise xor | `^` |
| bitwise or | `\|` |

- Parentheses group as usual.
- Numbers: decimal `42`, hex `0x2A` or `2Ah`, binary `0b101010`.
- Character literals: `'A'`, and escapes `'\n'` `'\t'` `'\r'` `'\0'` `'\\'`
  `'\''`.
- Arithmetic is 24-bit. `>>` is an arithmetic (sign-preserving) shift; `/`
  and `%` truncate toward zero, as in C (`-17/5` is `-3`).
- Division or remainder by zero stops with `ERROR: division by zero in
  expression`.
- Negative results are written as negative decimals (`lc r0,-3`), which
  `cor24-asm` accepts.

## Macros

```
MACRO name [&param1,&param2,...]
 body lines
MEND
```

A macro is invoked by writing its name as a statement, followed by
arguments separated by commas. Parameters are referred to by name (`&A`) or
by position (`&1` to `&9`):

```
MACRO PUSH2 &A,&B
 push &A
 push &B
MEND
MACRO POP2
 pop &2
 pop &1
MEND
 PUSH2 r0,r1
 POP2 r0,r1
```

Output:

```
 push r0
 push r1
 pop r1
 pop r0
```

- Up to 256 macros, names up to 31 characters, up to 16 named parameters
  with names up to 31 characters. All macro bodies together can use 64 KB.
- `\@` expands to a number unique to each expansion (`0001`, `0002`, ...),
  so a label like `L\@:` inside a macro is distinct every time the macro is
  used (see `PUTC` above).
- A missing argument expands to nothing.
- Symbols in a macro's output are substituted like any other line, so
  `PUTC 'H'` produces `lc r0,72`.
- Arguments are separated by commas; an argument ends at a comma, blank or
  end of line.

## Conditional assembly

Conditional assembly includes or skips source lines at assembly time:

```
SET DEBUG,1
SET LEVEL,2
IFDEF DEBUG
 nop
ENDIFASM
IFEQ LEVEL,3
 add r0,3
ELSEASM
 add r0,1
ENDIFASM
IFNDEF RELEASE
 lc r1,0
ENDIFASM
```

Output:

```
 nop
 add r0,1
 lc r1,0
```

| Directive | Includes the block when |
|---|---|
| `IFDEF name` | the symbol is defined and not 0 |
| `IFNDEF name` | the symbol is not defined |
| `IFEQ name,expr` | the symbol's value equals the expression |
| `IFNE name,expr` | the symbol's value differs from the expression |
| `ELSEASM` | the preceding condition was false |
| `ENDIFASM` | ends the block |

Blocks nest up to 32 deep.

## Structured control flow

Structured statements compare a register with a value and generate the
labels and branches. Conditions are written `cc, register, value`:

| Condition | True when |
|---|---|
| `cc_eq` | register = value |
| `cc_ne` | register != value |
| `cc_lt` | register < value (signed) |
| `cc_lu` | register < value (unsigned) |
| `cc_zset` | the C flag is set (no operands; test a compare you just did) |
| `cc_zclr` | the C flag is clear |

The value can be a register, a number, or a symbol expression. A constant is
loaded into a scratch register that is saved and restored around the
compare (`push r2` / `lc r2,...` / `pop r2`), so the generated code changes
no registers except the ones your own code changes.

### IF / ELSEIF / ELSE / ENDIF

```
LIMIT EQU 10
IF cc_lt, r0, LIMIT
 add r0,1
ELSE
 lc r0,0
ENDIF
```

Output:

```
 push r2
 lc r2,10
 cls r0,r2
 pop r2
 brt _hlif_3_skip
 bra _hlif_1_false
_hlif_3_skip:
 add r0,1
 bra _hlif_2_end
_hlif_1_false:
 lc r0,0
_hlif_2_end:
```

`ELSEIF cc, reg, value` adds further branches; `ELSE` is optional.

### DO / DOEXIT / ITERATE / ENDDO

`DO` ... `ENDDO` loops forever; `DOEXIT cc, reg, value` leaves the loop when
the condition is true, and `ITERATE` jumps back to the top.

```
 lc r0,0
DO
 add r0,1
 DOEXIT cc_eq, r0, 5
ENDDO
```

Output:

```
 lc r0,0
_hldo_1_top:
 add r0,1
 push r2
 lc r2,5
 ceq r0,r2
 pop r2
 brf _hldo_3_skip
 bra _hldo_2_end
_hldo_3_skip:
 bra _hldo_1_top
_hldo_2_end:
```

### SELECT / WHEN / OTHERWISE / ENDSEL

```
SELECT r0
WHEN 1
 lc r1,10
WHEN 2
 lc r1,20
OTHERWISE
 lc r1,0
ENDSEL
```

Each `WHEN value` arm runs when the selected register equals the value;
`OTHERWISE` runs when no arm matched.

### Nesting and long blocks

IF, DO and SELECT each nest up to 32 deep. Generated labels
(`_hlif_N_...`, `_hldo_N_...`, `_hlsel_N_...`) are unique across the whole
program, so avoid starting your own labels with `_hl`.

Every structured jump is emitted as `bra` when the target is within reach
and otherwise as `push r2` / `la r2,L_far` / `jmp (r2)` with a matching
`pop r2` at the target, so a block can be any size. hlasm decides this by
sizing its output in a first pass; nothing needs to be marked by hand.
Demo d40 shows the long form.

## Data directives

`.byte` and `.word` pass through (with symbols substituted). hlasm also
lowers these conveniences to `.byte` lists:

```
msg:
.asciz "Hi\n"
.ascii "\x41B"
.space 3
.fill 2,0x7F
```

Output:

```
msg:
.byte 72,105,10,0
.byte 65,66
.byte 0,0,0
.byte 127,127
```

| Directive | Produces |
|---|---|
| `.ascii "text"` | the characters |
| `.asciz "text"` | the characters and a terminating 0 |
| `.space n` | `n` zero bytes |
| `.fill n,v` | `n` bytes of value `v` |

String escapes: `\n` `\t` `\r` `\0` `\\` `\"` `\'` and `\xNN` (two hex
digits). Any other escape stops with `ERROR: unknown escape in string or
character literal`.

`cor24-asm` does not accept label arithmetic in `.word` (`.word msg+1`); use
a separate label instead.

## Multiple source files: INCLUDE and COPY

Larger programs are split into members: a main source plus named files that
the main source pulls in with `INCLUDE name` or `COPY name` (the HLASM
spelling, typically used for macro and symbol libraries). Members can
include other members, up to 8 deep.

The files are described by a **source set**, and
`reg-rs/run_bootstrap_sourceset.sh` builds the images, loads them and runs
hlasm:

```
# prog.sourceset
ROOT .
MAIN prog.hlasm
COPY libmac macros.hlasm
COPY libsym symbols.hlasm
```

```
; macros.hlasm
MACRO PUSH2 &A,&B
 push &A
 push &B
MEND
```

```
; symbols.hlasm
K EQU 7
```

```
; prog.hlasm
COPY libmac
COPY libsym
 PUSH2 r0,r1
 lc r2,K
```

```bash
bash reg-rs/run_bootstrap_sourceset.sh prog.sourceset 5000000 -q
```

Output (after the emulator's `Loaded ...` lines):

```
 push r0
 push r1
 lc r2,7
```

Source-set lines:

| Line | Meaning |
|---|---|
| `MAIN file.hlasm` | the main source |
| `INCLUDE name file` / `COPY name file` | a member available under `name` |
| `SOURCESET other.sourceset` | read another source set (for sharing member lists) |
| `PROFILE file` | read shared defaults (e.g. `demos/default.profile`) |
| `ROOT dir` | directory that file names are relative to |
| `MAINADDR` / `EXTRAADDR` / `ALIGN` | load addresses and alignment (rarely needed) |

A source set lifts the 32,767-byte main-source limit; together, all files
fit in the 256 KB window at 0x080000-0x0BFFFF. Today a source set can name
3 members, with names of up to 8 characters (see
[Not supported yet](#not-supported-yet)). Demos d23, d24 and d34 show
complete source sets.

## Listings, cross-reference and diagnostics

Four switches add information to the output as `;` comments, so the result
still assembles. Each is turned on by `SET name,1` anywhere in the source:

| Switch | Adds |
|---|---|
| `HLANN` | `; HLASM IF ...` / `; HLASM THEN` / `; HLASM ENDIF` markers around structured code |
| `HLIST` | lines for each `COPY`, macro definition, macro expansion and `EQU` |
| `HLXREF` | a cross-reference at the end: members copied, macros defined and how often each was expanded, symbols |
| `HLDIAG` | warnings such as unknown mnemonics and undefined symbols, with source and line |

Annotated structured code (`SET HLANN,1`):

```
; HLASM IF cc_eq, r0, 0
 push r2
 lc r2,0
 ceq r0,r2
 pop r2
 brt _hlif_3_skip
 bra _hlif_1_false
_hlif_3_skip:
; HLASM THEN
 add r1,1
_hlif_1_false:
_hlif_2_end:
; HLASM ENDIF
```

A diagnostic (`SET HLDIAG,1`, then `SET RESULT,FLAG+UNDEF`):

```
; !! hlasm: HLDIAG active at src0:5
; !! hlasm: undefined symbol 'UNDEF' at src0:5
```

A cross-reference (`SET HLXREF,1`):

```
; HLASM XREF BEGIN
; HLASM XREF COPY libmac
; HLASM XREF MACRO PUSH2
; HLASM XREF EXPAND PUSH2 1
; HLASM XREF END
```

## Limits and error messages

hlasm checks every limit. Exceeding one stops hlasm with a single `ERROR:`
line; nothing is silently truncated.

| Item | Limit | Error |
|---|---|---|
| Source line | 256 characters | `input line longer than 256 characters` |
| Symbols | 512 | `symbol table overflow (512 symbols)` |
| Symbol name | 31 characters | `symbol name longer than 31 characters` |
| Macros | 256 | `macro table overflow (256 macros)` |
| Macro name | 31 characters | `macro name longer than 31 characters` |
| Macro parameters | 16 | `more than 16 macro parameters` |
| Parameter name | 31 characters | `macro parameter name longer than 31 characters` |
| All macro bodies | 64 KB | `macro body pool overflow (65536 bytes)` |
| Expanded macro line | 256 characters | `expanded macro line longer than 256 characters` |
| Conditional nesting | 32 | `conditional assembly nested deeper than 32` |
| IF / DO / SELECT nesting | 32 each | `IF nested deeper than 32` (and DO, SELECT) |
| Division | non-zero divisor | `division by zero in expression` |
| String escapes | see above | `unknown escape in string or character literal` |

For example, `SET THIS_NAME_IS_MUCH_TOO_LONG_FOR_HLASM,1` gives:

```
ERROR: symbol name longer than 31 characters
```

Values are 24-bit and wrap like COR24 arithmetic. Structured labels and
`\@` numbers have no practical limit.

## Not supported yet

These are planned (see `docs/limits-and-lifting-plan.md` for the schedule):

- **Macros calling macros, and directives inside macro bodies.** A macro
  body is expanded as text: a macro name or `IF`/`IFDEF` inside a body is
  copied to the output rather than processed.
- **Default and keyword parameters** (`&V=5`, `NAME=value`).
- **More include members**: a source set can name 3 members with names of
  up to 8 characters, and error messages do not yet name the member and
  line.
- **Compound conditions** (`IF cc_eq,r0,1,AND,...`) and record layouts
  (`DSECT`).
- **Labels as values.** Labels are resolved by `cor24-asm`, not hlasm, so
  they cannot be used in `EQU`, `SET` or conditions.

## Further reading

- `demos/README.md`: the demo programs (d01-d41) and what each shows.
- `docs/design.md`: the language design and lowering rules.
- `docs/limits-and-lifting-plan.md`: every limit, known issue and the plan
  for lifting the rest.
- `docs/structured-jump-relaxation.md`: how long-range structured jumps work.
- `docs/architecture.md`: hlasm's internals and memory layout.
