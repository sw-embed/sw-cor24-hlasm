# Product Requirements Document

## Product Name

**HLASM Macro-Assembler for COR24**

## Tagline

An IBM HLASM-inspired macro-assembler for the COR24 24-bit RISC ISA, written entirely in COR24 assembly.

## Purpose

sw-cor24-hlasm provides a macro-assembler that:
- accepts HLASM-inspired structured assembly source from an in-memory buffer
- expands macros with parameters and local labels
- evaluates conditional assembly (IFDEF, IFEQ, SET symbols)
- lowers structured control flow (IF/DO/SELECT) to plain labels and branches
- produces plain COR24 assembly output via UART

The implementation language is **COR24 assembly**. There is no high-level
language intermediary -- the macro-assembler is itself a COR24 assembly program.

## Users

Primary users are:
- the project author
- COR24 ecosystem developers wanting structured assembly
- students learning about macro-assembler implementation
- people interested in historically-grounded assembler technology

## Core Value

- historical authenticity (macro-assemblers were originally implemented in assembler)
- educational visibility (every byte of the macro-assembler is inspectable COR24 assembly)
- structured assembly on a minimal 24-bit RISC machine
- a compelling demo of a self-hosting-adjacent tool on COR24

## Scope

### In Scope (Victory Line A)

- MACRO/MEND with positional and keyword parameters, defaults, local labels
- Nested macro expansion with unique label generation
- Conditional assembly: IFDEF, IFNDEF, IFEQ, IFNE
- Assembly-time SET symbols (integers)
- Structured IF: IF/ELSEIF/ELSE/ENDIF lowering to branches
- Structured DO: DO/DOEXIT/ITERATE/ENDDO lowering to loops
- Structured SELECT: SELECT/WHEN/OTHERWISE/ENDSEL lowering to dispatch
- Plain assembly passthrough (non-structured lines pass through unchanged)

### Out of Scope

- Types, type system, record declarations
- General-purpose compile-time expression language
- Optimizing transformations
- Relocatable object format or linker
- Runtime abstractions or hidden semantics
- COPY/include (deferred)
- PROC/ENDP, STRUCT, REPT (Victory Line B)

## Goals

### G1. Structured control flow

The macro-assembler shall accept IF/ELSEIF/ELSE/ENDIF, DO/ENDDO, and
SELECT/WHEN/ENDSEL and lower them to plain labels and branches.

### G2. Real macros

The macro-assembler shall support MACRO/MEND with parameters, defaults,
local labels, and nested invocation.

### G3. Conditional assembly

The macro-assembler shall support IFDEF, IFEQ, and SET symbols for
compile-time decisions.

### G4. COR24 assembly implementation

The entire macro-assembler shall be written in COR24 assembly. No C, Rust,
Python, or other high-level language code.

### G5. Shell script build system

Build, test, and demo shall be driven by shell scripts and Make, following
the patterns established by sibling repos (sw-cor24-forth, sw-cor24-rpg-ii).

### G6. Regression testing with reg-rs

Tests shall use `reg-rs` for golden-output regression testing, consistent
with other COR24 language implementations.

## Constraints

### C1. Implementation language

COR24 assembly only. Shell scripts for build/test orchestration.

### C2. Target platform

COR24 emulator (`cor24-run`) and COR24 FPGA hardware.

### C3. Memory model

All data in COR24 address space (1 MB SRAM + 8 KB EBR stack).

### C4. Register constraints

3 general-purpose registers (r0, r1, r2), frame pointer (fp), stack pointer (sp).

### C5. I/O model

UART at 0xFF0100. Input source loaded via `--load-binary`. Output emitted via UART.

## Success Criteria

### Phase 1 success

A simple macro can be defined, invoked, and the expanded output emitted
via UART as valid COR24 assembly.

### Phase 2 success

Structured IF/DO/SELECT blocks lower correctly to labels and branches.

### Phase 3 success

Conditional assembly (IFDEF/IFEQ) works correctly.

### Final success

A non-trivial COR24 program written using HLASM macros assembles and runs
correctly on `cor24-run`.
