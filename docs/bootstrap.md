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

## Step 11 Memory Map

The first explicit bootstrap-oriented map is now:

- `0x07F000`: source-switch config block
- `0x080000-0x0BFFFF`: preloaded ASCII source/include buffers
- `0x0C0000-0x0C055E`: `hlasm` runtime arena
- `0xFEE000-0xFEEBFF`: preferred 3K EBR stack (`cor24-run --stack-kilobytes 3`)

The current runtime arena packs the mutable assembler state into middle SRAM:

- line buffer
- source descriptor table and counters
- source-return stack for include-style buffer calls
- macro table and macro body pool
- expansion buffer state
- symbol table
- conditional stack

That keeps the bootstrap input side in low SRAM, keeps mutable assembler-owned
state out of the loaded source window, and leaves the rest of SRAM available
for future include growth, larger source windows, or an eventual SRAM fallback
stack if the 3K EBR stack proves too tight for later self-hosting stages.

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

The current source-switch path uses a small config block at `0x07F000` with:

- `+0`: extra-buffer count
- `+3`: first extra `(base,len)` record
- then additional 6-byte `(base,len)` records
- `+21`: optional main-source base override
- `+24`: optional main-source length override
- `+27`: include-name count
- `+30`: first include record as `(slot,name[9])`

Step 17 keeps that binary layout, but the named-include demos no longer treat
the low-SRAM block as hand-authored bytes. A tiny shell builder now emits the
same config image from readable manifest files with `main`, `extra`, and
`include` records, so bootstrap demos can describe include-table contents in
source-friendly text while `hlasm.s` continues to consume the unchanged binary
format at `0x07F000`.

Step 18 adds one more layer above that builder for bootstrap runs: a loader
spec written in assembler-flavored text. The current named-include demos use
`MAIN file@addr`, `SRCBUF slot,file@addr`, and `INCLUDE name,slot`, and the
host-side runner derives lengths from the loaded `.bin` files before emitting
the same binary config block. That keeps `hlasm.s` and the runtime INCLUDE
path unchanged while moving the named-buffer declarations out of `reg-rs`
internals and into demo-adjacent source files.

Step 19 applies that same loader workflow to a larger bootstrap-shaped source
set instead of only tiny demos. The split `hlasm0` proof carries its named
include declarations in `bootstrap/hlasm0_loader.hlasm`, loads separate source
buffers for the macro block and I/O block, and still feeds the unchanged
binary config image plus the normal runtime INCLUDE path in `hlasm.s`.

Step 20 generalizes that pattern again with a bootstrap source-set runner.
`bootstrap/hlasm0.sourceset` names one main `.hlasm` source and any number of
named include-source files, the host-side runner builds the corresponding
`.bin` files, assigns the standard bootstrap load addresses, emits the same
low-SRAM config image, and then invokes the unchanged runtime INCLUDE path.

Step 21 folds that workflow into the repo's normal entry points. The split
bootstrap proof can now be launched with `./build.sh bootstrap` or
`just bootstrap`, so larger multi-file bootstrap trees do not need custom
host-side command strings in order to build source images, map include
buffers, and run stage0 with the unchanged config layout and INCLUDE path.

Step 22 makes the source-set model less brittle for growth. Source sets can
now set a shared `ROOT`, override the main/extra base windows when needed, and
choose an alignment for packed include buffers. The host-side runner assigns
extra-buffer addresses from the actual built `.bin` sizes instead of assuming
every include file needs the next fixed 4 KB window.

Step 23 adds a small profile layer on top of that source-set grammar. A source
set can now start with `PROFILE default.profile` to pull in shared host-side
layout defaults such as the standard main/extra windows and buffer alignment,
then override only the pieces that differ for a particular bootstrap tree.

Step 24 extends that grammar with `SOURCESET child.sourceset`, so a larger
bootstrap tree can be assembled from smaller source-set fragments instead of
one flat file. The split `hlasm0` proof now composes separate main/include
fragments while still driving the same unchanged low-SRAM config image and
runtime INCLUDE path.

`hlasm.s` currently walks the source portion of that table into a small
in-memory descriptor set, which is enough to model include-like source
chaining with multiple preloaded ASCII buffers. That keeps the input side
compatible with repeated `cor24-run --load-binary ...@addr` flags today while
leaving room for a later heap-backed descriptor arena.

When the main override words are zero, stage0 keeps the default main window at
`0x080000/4096`. When they are non-zero, stage0 uses the patched main source
window and still appends extra source buffers from the legacy record area.

The first directive-driven source switch is now `SRCBUF <slot>`. It activates
the chosen preloaded source-buffer slot directly and rewinds that descriptor to
position zero. This is still a minimal bootstrap mechanism: slot selection is
numeric, target-native, and intentionally simple, but it lets a patched main
source explicitly pull in the next preloaded buffer instead of depending only
on EOF-driven handoff.

Step 14 adds `INCBUF <slot>` on top of that same table. `INCBUF` pushes the
current `(slot, position)` onto a tiny runtime source-return stack, rewinds the
target slot, and switches into it. When the included buffer reaches EOF,
`hlasm` restores the caller slot/position and resumes reading the original
source stream. Plain `SRCBUF` still behaves as a direct non-returning switch.

Step 15 adds `INCLUDE <name>`, which resolves a short ASCII include name
through the appended low-SRAM include table and then reuses the same return
stack path as `INCBUF`. Numeric `SRCBUF` and `INCBUF` remain available for the
lowest-level bootstrap flows, while `INCLUDE` is the first readable layer for
self-hosting source splits.

Step 16 keeps that same config block and runtime arena layout, but proves the
named-include path can nest: a patched main buffer can `INCLUDE mid`, `mid`
can `INCLUDE tail`, and the assembler unwinds from `tail` back into `mid`
before returning to the main source stream.

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
