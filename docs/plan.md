# Implementation Plan

## Milestones

### M1: Project Scaffold + Passthrough
Goal: Rust binary that reads .hlasm and writes .s, passing plain assembly
through unchanged.

Deliverables:
- Cargo project with `hlasm` binary crate
- CLI argument parsing (-o, -l, -I, -D)
- Line-based input: pass non-structured lines through to output
- Source mapping comments on output lines
- Build script (`scripts/build.sh`)
- reg-rs test: hello-world passthrough
- reg-rs test runner script (`scripts/test.sh`)

Exit criteria: `echo "nop" | hlasm` outputs `nop` and `cor24-run` accepts it.

### M2: Lexer + Tokenizer
Goal: Tokenize .hlasm input into a structured token stream.

Deliverables:
- Token types: keyword, mnemonic, register, number, string, label, comment,
  operator, comma, paren, newline
- Lexer handles: labels with colon, `;` and `#` comments, hex/decimal numbers,
  register names, mnemonic names, macro keywords
- reg-rs tests for tokenization edge cases

### M3: MACRO/MEND + Expansion
Goal: Define and invoke macros with parameters and local labels.

Deliverables:
- MACRO/MEND parsing (collect body tokens)
- Macro invocation (match name, bind parameters)
- Positional parameters with `\name` substitution
- Default parameter values
- Local label generation with `\@`
- Nested macro calls (macro body invokes another macro)
- Unique label counter (global, monotonically increasing)
- reg-rs tests: simple macro, parameterized macro, default params,
  local labels, nested macros, multiple invocations

### M4: COPY / Include
Goal: Include external .hlasm files as macro libraries.

Deliverables:
- COPY directive parsing
- File search: relative to including file, `lib/`, `-I` paths
- Recursive include (with depth limit)
- COPY inside conditional (deferred evaluation)
- `lib/` directory with placeholder file
- reg-rs tests: COPY from lib/, COPY with -I path, nested COPY

### M5: Conditional Assembly
Goal: Compile-time conditionals and SET symbols.

Deliverables:
- SET directive (integer symbols)
- -D command-line symbol definition
- IFDEF / IFNDEF (symbol defined / not defined)
- IFEQ / IFNE (integer comparison)
- ELSEASM / ENDIFASM
- Nested conditionals
- reg-rs tests: IFDEF true/false, IFEQ equal/not-equal, nesting,
  -D override, SET/IFDEF interaction

### M6: Structured IF
Goal: IF/ELSEIF/ELSE/ENDIF lowering to labels + branches.

Deliverables:
- Parse IF with condition specifier and operands
- Parse optional ELSEIF chain
- Parse optional ELSE
- Parse ENDIF
- Lower to ceq/cls/clu + brf/brt + generated labels
- Handle constant comparisons (load into register first)
- Handle cc_zset / cc_zclr (no compare needed)
- Source mapping comments in lowered output
- reg-rs tests: simple IF, IF/ELSE, IF/ELSEIF/ELSE, nested IF,
  constant comparison, zero flag conditions, end-to-end with cor24-run

### M7: Structured DO
Goal: DO/DOEXIT/ITERATE/ENDDO lowering to loops.

Deliverables:
- Parse DO (infinite loop)
- Parse DO WHILE (pre-condition loop)
- Parse DOEXIT with condition
- Parse ITERATE (jump to loop top)
- Parse ENDDO
- Lower to labels + branches
- ITERATE goes to condition evaluation (for WHILE) or loop top (for infinite)
- DOEXIT goes past ENDDO
- reg-rs tests: infinite loop, WHILE loop, DOEXIT, ITERATE,
  nested DO, end-to-end with cor24-run (e.g., count-down loop)

### M8: Structured SELECT
Goal: SELECT/WHEN/OTHERWISE/ENDSEL lowering to dispatch.

Deliverables:
- Parse SELECT with register operand
- Parse WHEN with constant value
- Parse OTHERWISE
- Parse ENDSEL
- Lower to compare-and-branch chain
- Handle 0 specially (use z register)
- Handle constants > 127 (la + lw pattern)
- reg-rs tests: 2-way dispatch, multi-way dispatch, OTHERWISE,
  nested SELECT, end-to-end with cor24-run (e.g., command interpreter)

### M9: Listing + Diagnostics
Goal: Listing mode showing macro expansion and lowered code.

Deliverables:
- `-l` flag produces listing to stdout or file
- Listing format: source line number, structured source, lowered assembly
- Macro expansion trace (optional verbosity level)
- Error messages with source line numbers
- reg-rs tests: listing output format verification

### M10: Standard Macro Library
Goal: Reusable COR24 macro library in `lib/`.

Deliverables:
- `lib/cor24_base.hlasm` -- register names, UART addresses, common equates
- `lib/cor24_uart.hlasm` -- EMIT_CHAR, READ_CHAR, PRINT_STRING macros
- `lib/cor24_stack.hlasm` -- PUSHREG, POPREG, SAVE_CONTEXT, RESTORE_CONTEXT
- `lib/cor24_debug.hlasm` -- conditional debug output macros
- End-to-end tests using library macros

## Dependency Graph

```
M1 (scaffold) --> M2 (lexer) --> M3 (macros) --> M4 (COPY)
                                            \--> M5 (conditionals)
M3 + M5 --> M6 (IF) --> M7 (DO) --> M8 (SELECT) --> M9 (listing)
                                                        \--> M10 (library)
```

M6, M7, M8 can be developed in any order after M3+M5.
M9 and M10 are independent of each other.

## Phase 1 (This Saga)

The first saga implements through M1-M3, establishing the foundation:

1. M1: Project scaffold + passthrough
2. M2: Lexer + tokenizer
3. M3: MACRO/MEND + expansion

This gives us a working tool that can define macros, invoke them, and produce
valid .s output. Structured control flow and conditionals come in the next saga.

## Testing Throughout

Every milestone includes reg-rs tests. The test prefix is `hlasm_`.

Test naming convention:
- `hlasm_m1_passthrough` -- M1 tests
- `hlasm_m2_tokenize_*` -- M2 tests
- `hlasm_m3_macro_*` -- M3 tests
- `hlasm_m4_copy_*` -- M4 tests
- etc.

Each test follows the sw-cor24-forth pattern:
- `.rgt` file with command, timeout, preprocess, exit_code, desc
- `.out` file with golden baseline
- Run via `reg-rs run -p hlasm --parallel`
