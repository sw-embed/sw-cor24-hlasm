# Implementation Plan

## Approach

Single COR24 assembly file (`hlasm.s`), built up incrementally.
Shell scripts for build/test/demo. `reg-rs` for regression tests.
Follows sw-cor24-forth and sw-cor24-rpg-ii patterns directly.

## Step 1 -- Skeleton and UART output

Set up `hlasm.s` with reset vector, UART emit subroutine, and a halt loop.
Verify it assembles and runs with `cor24-run`.

**Deliverable**: `hlasm.s` prints "HLASM" to UART and halts.

**Test**: `reg-rs` golden output contains "HLASM".

## Step 2 -- Source buffer reader

Implement subroutine to read characters from an in-memory source buffer.
Load a small test source via `--load-binary` and verify characters are
read and echoed correctly.

**Deliverable**: `_read_char`, `_peek_char`, `_skip_whitespace` subroutines.
Source buffer descriptor layout.

**Test**: load source text, echo first N characters to UART.

## Step 3 -- Scanner / tokenizer

Implement a scanner that reads characters and produces tokens.
Recognize: keywords (MACRO, MEND, IF, ENDIF, DO, ENDDO, SELECT, etc.),
mnemonics, register names, numbers (decimal, hex), labels, identifiers,
comments, operators.

**Deliverable**: `_next_token`, `_scan_number`, `_scan_ident`, `_scan_keyword`.
Token type enum in memory.

**Test**: scan a small source, print token types/values to UART.

## Step 4 -- Line reader and passthrough

Implement line-by-line reading from the source buffer. Pass non-structured
lines through to UART output unchanged. Handle comments, labels, empty lines.

**Deliverable**: `_read_line`, `_emit_line`, passthrough main loop.

**Test**: load a simple .s program as source, emit it unchanged via UART.

## Step 5 -- Macro table and MACRO/MEND parsing

Implement the macro table data structure. Parse MACRO/MEND definitions:
store name, parameters, defaults, and body location in the table.

**Deliverable**: macro table layout, `_parse_macro_def`, `_lookup_macro`.

**Test**: define a macro, print its name and param count via UART.

## Step 6 -- Macro expansion

Implement macro invocation: look up macro in table, substitute parameters,
generate unique local labels for `\@`. Emit expanded body to output.

**Deliverable**: `_expand_macro`, `_substitute_params`, unique label counter.

**Test**: define PUSHREG macro, invoke it twice, verify expanded output.

## Step 7 -- Conditional assembly (SET, IFDEF, IFEQ)

Implement SET symbol definition and lookup. Evaluate IFDEF/IFNDEF
(symbol defined/not defined) and IFEQ/IFNE (integer comparison).
Skip or include sections based on conditions.

**Deliverable**: `_set_symbol`, `_lookup_symbol`, `_eval_conditional`.

**Test**: SET DEBUG,1; IFDEF DEBUG -> emit "debug"; verify output.

## Step 8 -- Structured IF lowering

Implement IF/ELSEIF/ELSE/ENDIF parsing and lowering to labels + branches.
Handle condition specifiers (cc_eq, cc_lt, etc.). Generate unique branch
target labels.

**Deliverable**: `_parse_if`, `_lower_if`, label generation for blocks.

**Test**: IF/ELSE block produces correct branch output.

## Step 9 -- Structured DO lowering

Implement DO/DOEXIT/ITERATE/ENDDO parsing and lowering to loops.

**Deliverable**: `_parse_do`, `_lower_do`.

**Test**: DO loop produces correct loop structure.

## Step 10 -- Structured SELECT lowering

Implement SELECT/WHEN/OTHERWISE/ENDSEL parsing and lowering to
compare-and-branch dispatch.

**Deliverable**: `_parse_select`, `_lower_select`.

**Test**: SELECT/WHEN produces correct dispatch chain.

## Step 11 -- Integration demo

Wire up all components. Process a non-trivial .hlasm source that uses
macros, conditionals, and structured control flow. Verify the output
assembles and runs correctly on `cor24-run`.

**Deliverable**: example .hlasm program, demo script, `reg-rs` test.

## Deferred

- COPY/include (file-based macro libraries)
- PROC/ENDP (procedure scaffolding)
- STRUCT/ENDSTRUCT (data layout)
- REPT (assembly-time repetition)
- Listing mode and xref
- Error recovery and diagnostics
- String SET symbols
