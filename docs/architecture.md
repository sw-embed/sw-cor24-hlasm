# Architecture

## Overview

sw-cor24-hlasm is a **macro-assembler front-end** for the COR24 24-bit RISC ISA.
It reads HLASM-inspired structured assembly source and lowers it to plain COR24
assembly (`.s` files) that the existing Rust-based assembler in sw-cor24-emulator
(`cor24-run`) can assemble and execute.

**Product statement**: A COR24 structured macro-assembler front-end that lowers
HLASM-inspired control-flow and macro constructs into ordinary COR24 assembly.

## Processing Pipeline

```
.hlasm source
     |
     v
  [HLASM Preprocessor]  -- macro expansion, conditional assembly, COPY/include
     |
     v
  [Structured Lowering] -- IF/DO/SELECT/PROC -> labels + branches
     |
     v
  plain .s output  -->  cor24-run --assemble / --run
```

The tool is a **preprocessor**, not a replacement assembler. It produces plain
`.s` files that are byte-compatible with the existing `cor24-run` assembler.

## Component Architecture

```
hlasm
 |
 +-- lexer      -- tokenize .hlasm source into tokens
 +-- parser     -- parse macro defs, conditionals, structured blocks, instructions
 +-- expander   -- expand macro invocations (scoped locals, nested calls)
 +-- cond       -- evaluate conditional assembly (SET symbols, IFASM, etc.)
 +-- lower      -- lower structured blocks to labels + branches
 +-- copy       -- resolve COPY/include directives
 +-- emit       -- emit plain .s output with source mapping comments
 +-- diagnose   -- listing, symbol table, xref, expansion trace
```

## Dependency Relationship

```
sw-cor24-hlasm  (this project -- macro-assembler front-end)
     |
     |  outputs plain .s files
     v
sw-cor24-emulator  (cor24-run -- assembler + emulator)
     |
     |  provides ISA crate
     v
cor24-isa         (shared ISA definitions: opcodes, registers, encoding)
```

No Rust crate dependency is required at runtime. The HLASM tool reads text
and writes text. Validation is done by piping output through `cor24-run`.

## Testing Strategy

Tests use **reg-rs** (golden-output regression testing), following the same
pattern as sw-cor24-forth:

1. Each test is a `.rgt` file with a command, expected exit code, and
   a preprocess filter to extract relevant output
2. Tests run via `reg-rs run -p hlasm --parallel`
3. The HLASM tool produces `.s` output; tests verify:
   - Correct lowering of structured constructs to plain assembly
   - Macro expansion correctness
   - Conditional assembly behavior
   - End-to-end: HLASM -> .s -> cor24-run -> UART output

## COR24 ISA Summary (Reference)

The target ISA has these constraints that shape the macro-assembler design:

- 24-bit words (3 bytes), little-endian
- 3 GPRs (r0, r1, r2), plus fp, sp, z, iv, ir
- Single condition flag C (set by ceq/cls/clu)
- Variable-length instructions: 1, 2, or 4 bytes (never 3)
- Branches: signed 8-bit PC-relative offset (-128..+127), +4 pipeline bias
- Load destinations limited to r0, r1, r2 only (not fp, sp)
- ALU destinations limited to r0, r1, r2 only
- No mov r0,sp -- must use mov fp,sp; push fp; pop r0
- 16 MB address space: 1 MB SRAM + 8 KB EBR + I/O

## Key Design Decisions

1. **Text-in, text-out**: No binary dependency on cor24-isa crate.
   Validation is external (pipe through cor24-run).
2. **No runtime semantics**: Structured forms lower to labels + branches.
   No hidden runtime, no types, no expression evaluator beyond assembly-time.
3. **Source mapping**: Output .s includes comments mapping back to .hlasm
   source lines for debugging.
4. **Macro-local symbols**: Each macro expansion gets unique local labels
   to prevent collisions across invocations.
5. **Not a compiler**: This is deliberately limited. Complex logic belongs
   in PL/SW, not in the macro-assembler.

## File Layout (Planned)

```
sw-cor24-hlasm/
  docs/              -- documentation
  reg-rs/            -- reg-rs test specifications (.rgt) and baselines (.out)
  scripts/           -- build and test shell scripts
  src/               -- Rust source for the HLASM tool
  tests/             -- test .hlasm source files
  lib/               -- standard macro library files (.hlasm, COPY-able)
  examples/          -- example .hlasm programs
```

## Non-Goals

- No types, type system, or record system beyond lightweight layout helpers
- No general-purpose compile-time programming language
- No optimizing transformations (clean lowering only)
- No relocatable object format or linker changes
- No runtime abstractions hidden behind macros
- No expression semantics approaching C/PL/I/PL/SW
