# Bootstrap Plan

## Goal

Reach a first self-hosting milestone where `hlasm.s` can assemble a reduced
HLASM source for part of the assembler itself. The initial target is not full
self-hosting. It is a staged `hlasm0 -> hlasm1` path:

- `hlasm.s`: hand-written stage0 assembler in plain `.s`
- `bootstrap/hlasm0.hlasm`: reduced assembler source written in the subset
  stage0 already supports
- `hlasm1`: larger assembler source after structured lowering and stronger
  macro facilities land

## Minimum Self-Hosting Subset

`hlasm0` should stay within features already proven in the current tree:

- Plain assembly passthrough
- No-argument `MACRO` / `MEND`
- `SET`
- `IFDEF` / `IFNDEF`
- `IFEQ` / `IFNE`
- Comments and labels

The first self-hosting milestone explicitly excludes:

- Structured `IF` / `ELSEIF` / `ELSE` / `ENDIF`
- Structured `DO` / `SELECT`
- Macro parameter substitution as a required mechanism
- Source that depends heavily on `\@` local-label rewriting

## Current Blockers

The current `hlasm.s` is not ready to express the full assembler in its own
source language yet.

1. Structured control-flow lowering is still missing. A larger `hlasm1`
   source will want `IF` and `DO` to make the code legible.
2. Macro parameter substitution is not yet a safe dependency for bootstrap.
   `hlasm0` should therefore use only no-argument macros.
3. The current source tree is still centered on a single hand-written
   `hlasm.s`; there is not yet a maintained bootstrap-oriented source split.
4. The current default input window was sized for toy demos, not bootstrap-
   scale source. Stage0 needs enough source-buffer space to read larger ASCII
   source images.
5. The stage pipeline is still single-buffer and single-file in spirit.
   For real bootstrap work, source files and future include files should be
   loaded into memory buffers, then consumed as logical input streams while
   stage0 continues to emit plain `.s` text over UART.

## Buffer-Oriented Bootstrap Model

The bootstrap path should stay target-native:

- load ASCII HLASM source into memory buffers
- optionally load include-file text into additional buffers
- have `hlasm` read those buffers as input streams
- keep UART as the plain-assembly output channel

That preserves the current architecture while still allowing a multi-source
bootstrap workflow later.

Two existing COR24 patterns are directly relevant here:

- `sw-cor24-monitor/demos/monitor-editor-demo.sh` already uses repeated
  `--load-binary ...@addr` flags to place several binaries plus an ASCII text
  file into memory at once.
- `cor24-run` also supports `--patch addr=value`, which is useful for passing
  buffer pointers, include-table roots, or entry-state values after those
  buffers are loaded.

That means `hlasm` does not need a host-side include mechanism to get started.
Stage0 can consume source and include-file buffers entirely through the
existing emulator interface.

The current step-9 proof point uses a small fixed config block at `0x07F000`
to advertise an optional second source buffer. That is intentionally simple:
it proves the multi-buffer path now, and a future include mechanism can build
on the same descriptor idea without changing the target-native loading model.

## Step 8 Deliverable

This step introduces the first bootstrap-oriented split:

- `bootstrap/hlasm0.hlasm`: reduced assembler-source fragment written in the
  current self-hosting subset
- `bootstrap/hlasm0.bin`: loadable source image for the emulator
- `reg-rs/hlasm_d16_bootstrap_hlasm0.rgt`: regression test proving stage0 can
  expand that source into plain `.s`
- a larger default source-buffer length in `hlasm.s`, so bootstrap-sized ASCII
  input is actually readable by stage0

## Demo Discipline

From this point on, every user-visible HLASM feature or bootstrap milestone
should land with:

- one source demo
- one `reg-rs` test
- one README/demo status update

That keeps the self-hosting path measurable instead of aspirational.
