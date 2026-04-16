# Product Requirements Document

## Problem Statement

Writing substantial COR24 assembly programs using the raw assembler (`cor24-run`)
is painful for anything beyond simple routines. Control flow requires manual
label management, branches are limited to +/-127 bytes, and there is no way
to reuse common patterns (UART I/O, register save/restore, stack frames) without
copy-paste.

This leads to:
- Branch-heavy, hard-to-read assembly ("label spaghetti")
- Repetitive boilerplate for common patterns
- No compile-time decisions (debug vs release, feature flags)
- No code reuse mechanism beyond COPY of plain source
- Fragile refactoring (changing a branch target may cascade)

## Solution

A macro-assembler front-end inspired by IBM HLASM that adds:
1. Structured control-flow (IF/ELSEIF/ELSE/ENDIF, DO/ENDDO, SELECT/ENDSEL)
2. Real macros with scoped locals and parameter substitution
3. Conditional assembly (IFDEF, IFEQ, feature flags)
4. COPY/include for reusable macro libraries
5. Listing and diagnostics for debugging expanded code

The tool reads `.hlasm` source and outputs plain `.s` files compatible with
`cor24-run`.

## Scope Definition

### In Scope (Victory Line A)

- MACRO/MEND with positional and keyword parameters, defaults, local labels
- Nested macro expansion with unique label generation
- COPY/include for macro library files
- Conditional assembly: IFDEF, IFNDEF, IFEQ, IFNE
- Assembly-time SET symbols (integers and strings)
- Structured IF: IF/ELSEIF/ELSE/ENDIF lowering to branches
- Structured DO: DO/DOEXIT/ITERATE/ENDDO lowering to loops
- Structured SELECT: SELECT/WHEN/OTHERWISE/ENDSEL lowering to dispatch
- Source mapping comments in output .s
- Listing mode with macro expansion trace
- Standard COR24 macro library (UART, register save/restore, stack helpers)

### Out of Scope (Deliberate Exclusions)

- Types, type system, record declarations
- General-purpose compile-time expression language
- Optimizing transformations on lowered code
- Relocatable object format or linker changes
- Runtime abstractions or hidden semantics
- High-level modules, classes, or procedures beyond light scaffolding
- PROC/ENDP (Victory Line B)
- STRUCT/ENDSTRUCT (Victory Line B)
- REPT (Victory Line B)

## User Stories

### US-1: Structured conditional assembly
As a COR24 assembly programmer, I want to write IF/ELSEIF/ELSE/ENDIF blocks
so that my code is readable without tracking manual labels and branches.

### US-2: Loop structures
As a COR24 assembly programmer, I want DO/ENDDO with DOEXIT and ITERATE
so that scanning loops and state machines are clear and maintainable.

### US-3: Dispatch tables
As a COR24 assembly programmer, I want SELECT/WHEN/OTHERWISE/ENDSEL so that
command dispatch and opcode handling is readable.

### US-4: Macro reuse
As a COR24 assembly programmer, I want MACRO/MEND with parameters so that
common patterns (UART I/O, register save/restore) are written once and reused.

### US-5: Macro-local labels
As a COR24 assembly programmer, I want local labels inside macros so that
macro invocations do not collide with each other or with outer labels.

### US-6: Conditional compilation
As a COR24 assembly programmer, I want IFDEF/IFEQ and SET symbols so that
I can build debug/release variants and feature-flagged code.

### US-7: Include libraries
As a COR24 assembly programmer, I want COPY so that I can organize macros
into reusable library files.

### US-8: Debug the expansion
As a COR24 assembly programmer, I want a listing that shows both my
structured source and the lowered assembly so I can verify correctness.

### US-9: End-to-end validation
As a COR24 assembly programmer, I want to pipe my .hlasm through the tool
and into cor24-run to verify my program runs correctly.

## Acceptance Criteria

1. A `.hlasm` file with IF/ELSE/ENDIF assembles and runs identically to
   hand-written branch equivalents
2. A macro defined with MACRO/MEND can be invoked multiple times without
   label collisions
3. COPY includes a file and its macros are available in the including file
4. IFDEF/IFNDEF correctly gates code sections based on SET symbols
5. SELECT/WHEN/ENDSEL produces correct compare-and-branch dispatch
6. DO/ENDDO with DOEXIT produces correct loop-with-exit patterns
7. All output .s is valid cor24-run input (assembles without errors)
8. Listing mode shows structured source alongside lowered assembly

## Success Metric

A programmer can write a COR24 program using structured macros that:
- Is more readable than equivalent hand-written assembly
- Assembles to byte-identical (or functionally equivalent) output
- Runs correctly on the cor24-run emulator

## Constraints

- Written in Rust (for consistency with the COR24 ecosystem)
- No Python, C, or other HLL in the toolchain
- Scripts for building; no make/cargo build required for end users
- Tests use reg-rs only (no Rust unit test framework for end-to-end)
- Output must be compatible with cor24-run assembler
- Must handle all COR24 ISA constraints (branch range, register limits, etc.)
