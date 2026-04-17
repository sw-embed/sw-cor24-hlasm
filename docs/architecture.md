# Architecture

## Overview

sw-cor24-hlasm is a **macro-assembler** for the COR24 24-bit RISC ISA,
written entirely in COR24 assembly. It reads HLASM-inspired structured
assembly source from an in-memory text buffer and emits plain COR24
assembly (`.s` output via UART).

The macro-assembler runs on the COR24 emulator (`cor24-run`) just like
sw-cor24-forth and sw-cor24-rpg-ii.

**Product statement**: A COR24 macro-assembler, written in COR24 assembly,
that processes HLASM-inspired source and produces plain COR24 assembly output.

## Processing Pipeline

```
.hlasm source (loaded into memory)
     |
     v
+-------------------------------+
| HLASM Macro-Assembler         |
|  (COR24 assembly program)     |
|   Scanner / tokenizer         |
|   Macro table lookup          |
|   Macro expansion             |
|   Conditional assembly eval   |
|   Structured lowering         |
|   Symbol table management     |
+-------------------------------+
     |
     v
UART output: plain .s assembly
     |
     v
cor24-run --assemble --run
```

The macro-assembler is a COR24 program that reads text and writes text.
It is not a host-side tool -- it runs on the target.

## Platform

COR24 24-bit RISC: 3 GP registers (r0-r2), fp, sp, z, iv, ir,
24-bit words, variable-length instructions (1/2/4 bytes), UART at 0xFF0100.

## Memory Layout

| Region | Address | Contents |
|--------|---------|----------|
| Code + immutable tables | 0x000000+ | HLASM macro-assembler assembly |
| Source config block | 0x07F000 | Extra-source descriptor config loaded by `--load-binary` |
| Source/include buffers | 0x080000-0x0BFFFF | Preloaded ASCII HLASM input buffers |
| Runtime arena | 0x0C0000-0x0C055E | Mutable assembler state in SRAM |
| Stack | 0xFEEC00 | Preferred 3K EBR stack (`--stack-kilobytes 3`) |

The runtime arena currently contains the line buffer, source descriptor table,
source-return stack, macro table/body pool, expansion buffer state, symbol
table, conditional stack, and a small include-lookup scratch word. This keeps
loaded source text and assembler-owned mutable state in separate SRAM regions,
which is the first bootstrap-oriented layout.

## Components

### Scanner
Reads input text character by character. Identifies keywords (MACRO, MEND,
IF, DO, SELECT, etc.), mnemonics, register names, numbers, labels, comments.
Produces a token stream in memory.

### Macro Table
Stores macro definitions: name, parameter list, body token stream.
Lookup on macro invocation. Supports nested macros.

Current compatibility baseline is intentionally narrower than full IBM HLASM:
simple `MACRO ... MEND` definitions are consumed rather than emitted, simple
invocation-by-name expansion is stable, positional `&1`/`&2` substitution
works, and HLASM-style named `&arg` substitution works. Full local-label
compatibility and broader macro robustness are still being hardened in later
steps.
Macro names up to 31 characters are supported, and repeated `\@` local-label
expansion now stays distinct across multiple macro definitions and invocations.
Macro bodies still expand directly to emitted plain-text lines; the assembler
does not yet reparse conditional-assembly or structured-control-flow
directives that appear inside macro bodies.

### Macro Expander
Substitutes positional `&N` and named `&name` parameters, with named
parameters rewritten onto the positional expansion path at record time.
Generates unique local labels (`\@` -> unique counter). Handles nested
expansion with depth limit.

### Conditional Assembly
Evaluates SET symbols, IFDEF, IFEQ at assembly time. Includes or excludes
source sections based on conditions.

### Structured Lowering
Transforms IF/ELSEIF/ELSE/ENDIF, DO/ENDDO, SELECT/WHEN/ENDSEL into plain
labels and branches. Generates unique branch target labels. Because raw COR24
branches only have an 8-bit PC-relative reach, structured lowering uses
long-range-safe forms for generated control flow: reversed short conditional
branches skip over unconditional `jmp` instructions, and generated
unconditional structured transfers emit `jmp` directly instead of `bra`.

### Symbol Table
Tracks labels, SET symbols, and macro names. Symbol lookup during expansion
and lowering.

### Output Emitter
Writes expanded, lowered assembly text to the output buffer. Flushes to UART.

## Register Allocation

External code generation still follows the Forth/RPG-II style register roles,
but internal `hlasm.s` helper routines now use a stricter calling convention
for correctness and predictability.

| Register | Use |
|----------|-----|
| r0 | Return value / caller-saved scratch |
| r1 | Return address from `jal`, volatile scratch |
| r2 | Callee-saved working register |
| fp | Frame pointer for subroutines |
| sp | Data stack (hardware push/pop) |

Internal helper ABI rules:

- A helper that writes `r2` must save and restore it before returning.
- Callers must assume `r0` and `r1` are clobbered by any helper call.
- `fp` and `sp` must always be restored by the callee.
- This convention is defensive rather than minimal: helper composition should
  stay correct even as implementations change internally.

## I/O Model

- **Input**: .hlasm source loaded into memory via `--load-binary`
- **Output**: plain .s assembly emitted via UART
- **UART**: character I/O at 0xFF0100

## Dependency Relationship

```
sw-cor24-hlasm (this project)
  |
  |  runs on
  v
sw-cor24-emulator (cor24-run -- assembler + emulator)
```

## Testing Strategy

Tests use **reg-rs** (golden-output regression testing), following the same
pattern as sw-cor24-forth and sw-cor24-rpg-ii:

1. Each test is a `.rgt` file with a `cor24-run` command
2. Input source loaded via `--load-binary`
3. Preprocess filter extracts UART output
4. Tests run via `reg-rs run -p hlasm --parallel`

## COR24 ISA Constraints

- 24-bit words (3 bytes), little-endian
- 3 GPRs (r0, r1, r2), plus fp, sp, z, iv, ir
- Single condition flag C (set by ceq/cls/clu)
- Variable-length instructions: 1, 2, or 4 bytes (never 3)
- Branches: signed 8-bit PC-relative offset (-128..+127), +4 pipeline bias
- Load destinations limited to r0, r1, r2 only (not fp, sp)
- ALU destinations limited to r0, r1, r2 only
- No mov r0,sp -- must use mov fp,sp; push fp; pop r0
- 16 MB address space: 1 MB SRAM + 8 KB EBR + I/O

## Build / Test

```bash
just build        # assemble check
just test         # run reg-rs regression suite
just demo         # run example
./build.sh        # build script
./demo.sh         # demo script
./demo.sh test    # test suite
```

All shell scripts for build/test. No Python/Rust/C in the project.
Follows sw-cor24-forth and sw-cor24-rpg-ii patterns.

## Non-Goals

- No types, type system, or record system
- No general-purpose compile-time programming language
- No optimizing transformations
- No relocatable object format or linker
- No runtime abstractions hidden behind macros
- No expression semantics approaching C/PL/I/PL/SW
