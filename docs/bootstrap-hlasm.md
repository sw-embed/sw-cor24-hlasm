# Bootstrapping hlasm in HLASM (future saga plan)

Status: plan only. This saga starts after the limits work in
`docs/limits-and-lifting-plan.md` has landed (see "Prerequisites").

## Goal

Rewrite hlasm in its own language. The maintained source becomes
`src/hlasm.hlasm` plus include members, using macros and structured control
flow where they make the code clearer. The `.s` that the assembler runs is
generated from that source by hlasm itself.

`docs/bootstrap.md` covers the earlier, much smaller milestone: the stage0
`hlasm.s` expanding the toy `bootstrap/hlasm0` source set. This document
covers porting the whole assembler.

## What "self-hosting" means here

hlasm turns HLASM into plain COR24 `.s`. It does not produce machine code.
`cor24-asm` and `cor24-emu` stay as the trusted base:

```
hlasm.hlasm --[hlasm running on cor24-emu]--> hlasm.s --[cor24-asm]--> hlasm.lgo
```

Self-hosting means **fixed point**: the assembler built from `hlasm.hlasm`,
given `hlasm.hlasm` as input, reproduces its own `.s` exactly.

```
stage0 = current hand-written hlasm.s (the seed)
stage1 = stage0 run on hlasm.hlasm  -> hlasm1.s
stage2 = hlasm1.s run on hlasm.hlasm -> hlasm2.s
require: hlasm1.s == hlasm2.s (byte-identical text)
```

Rewriting machine-code generation in HLASM, so that cor24-asm is no longer
needed, is out of scope.

## Starting point (measured 2026-10-31)

- `hlasm.s`: 12,268 lines, 159 KB of text.
  - 937 labels, 643 `jal` call sites, ~820 data directives.
  - The assembled image is about 20 KB (last load record at 0x4D7C), far
    below the config block at 0x07F000.
- Code idiom: every routine repeats the same prologue (`push fp` / `push r2`
  / `push r1` / `mov fp,sp`) and the matching epilogue. Every call site
  repeats `la r0,_fn` / `jal r1,(r0)` / `add sp,N`. Control flow is written
  as hand-made branch chains. These patterns are what macros and structured
  control flow will replace.
- Cost: roughly 1,000 emulated instructions per source byte for
  macro-heavy input, and the two relaxation passes add more. (The limits
  audit has the exact figures.) A ~130 KB HLASM source is therefore on the
  order of 10^8 instructions per run. That needs a budget like plsw's
  (`-n 2000000000`), not the reg-rs-sized budgets.

## Prerequisites (from the limits plan)

These must be lifted before the full assembler source can go through hlasm.
The numbers are tracked in `docs/limits-and-lifting-plan.md`.

1. **Source capacity.** The default main window is 4,096 bytes. The legacy
   config block has only 3 extra-buffer records, and include names are at
   most 8 characters. The whole 256 KB window at 0x080000–0x0BFFFF must be
   usable, with enough include slots for about 15–25 members.
2. **Symbol and macro tables** must hold an hlasm-sized program: hundreds of
   `SET` symbols and dozens of macros with bodies. No table may overflow
   silently; every overflow must be a diagnostic.
3. **Relaxation tables.** Structured label and jump ids are capped at 1,024.
   Beyond that, every jump takes the far form. That output is still correct
   and deterministic, but it is larger and slower. The tables should grow (or
   be indexed per routine) to well above hlasm's expected few thousand
   structured blocks.
4. **Lowering bugs:** DOEXIT polarity, `ceq` operand order, and `0b`
   literals. The rewrite must not inherit wrong lowering.
5. **Macro features the rewrite depends on:**
   - local labels (`\@`) that are safe across many expansions;
   - default and keyword parameters (B6);
   - conditional directives inside macro bodies (B5), so that one `CALL`
     macro can handle 0..N arguments.
6. **Diagnostics in include members (G6).** Errors must name the member and
   line, or a 159 KB port becomes undebuggable.
7. **Line length (G5).** The 128-byte buffer is fine for assembly, but it
   must give an error rather than truncate.

## Approach: refactor under an identity gate, then a behaviour gate

The port proceeds in small steps. Each step has a mechanical check, so the
assembler never stops working.

### Gate A: binary identity (phases 1–2)

`cor24-asm --bin` the `.s` produced from the HLASM sources, `cor24-asm --bin`
the reference `hlasm.s`, and `cmp` the two. As long as macros expand to
exactly the instructions they replace, the images are byte-identical. That
proves the refactor changed nothing.

### Gate B: behaviour (phases 3+)

Structured control flow changes label names and branch shapes, so the
images differ. The gate becomes: the whole reg-rs suite, run with the
candidate assembler in place of `hlasm.s`, produces identical outputs. This
requires the harness to take the assembler under test as a variable (for
example `HLASM_S=...` read by `scripts/run-kernel.sh` callers and the `.rgt`
commands).

### Gate C: fixed point (phase 4 onward)

`hlasm1.s == hlasm2.s` must hold, checked by a reg-rs test and a
`just selfhost` target.

## Phases (proposed saga steps)

1. **Harness.**
   - Add the `HLASM_S` override to the reg-rs commands, `build.sh`, and
     `demo.sh`.
   - Add `bootstrap/hlasm.sourceset` and `scripts/selfhost.sh`. The script
     builds the source images, runs stage N on them with a large budget,
     captures the `.s`, and runs gates A, B, or C.
2. **Mechanical split (gate A).**
   - Move `hlasm.s` verbatim into `src/` members: main/driver, lexer, line
     reader and buffers, macro table and expansion, conditional assembly,
     structured lowering, relaxation, emitters, and data.
   - Tie the members together with `INCLUDE`. Apart from that the members
     are plain `.s` passed through unchanged.
   - This proves capacity, include count, and cost at full scale before any
     source is rewritten.
3. **Macro library for the assembler's own idioms (gate A).**
   - Add `src/macros.hlasm` with `ENTER n` / `LEAVE`, `CALL fn,args...`
     (push args, `la`/`jal`, `add sp,3*n`), `ARG reg,i`, `LOCAL`, and
     constant-string and table macros.
   - Convert one member per step. Each conversion must stay byte-identical.
   - This step also feeds the shared macro library used by the tiny-C ports.
4. **Structured control flow (gate B).**
   - Replace hand-written branch chains with `IF`/`ELSEIF`/`ELSE`, `DO`/
     `DOEXIT`/`ITERATE`, and `SELECT`/`WHEN` (for example the keyword and
     token dispatch), one member at a time.
   - Run the full reg-rs suite after each member.
5. **Fixed point (gate C).**
   - Build stage1 and stage2 and require identical text.
   - Add the reg-rs test `hlasm_selfhost_fixed_point` and `just selfhost`.
6. **Switch over.**
   - `src/hlasm.hlasm` becomes the maintained source.
   - The repo-root `hlasm.s` becomes generated: it is the committed stage1
     output, regenerated by `just selfhost` and checked by gate C in
     `./build.sh test`. Commit it so that a fresh checkout can run hlasm
     with only cor24-asm and cor24-emu.
   - Keep the last hand-written stage0 as `bootstrap/stage0.s`. It is the
     re-bootstrap path if the generated seed is ever broken. Its source
     subset is frozen, and a CI check confirms that it still reaches the
     fixed point.
7. **Docs and demo.** Update README, architecture, and `docs/bootstrap.md`.
   Add a demo that shows the size and readability of `hlasm.hlasm` against
   `hlasm.s`, and the fixed point being reached.

## Rules after switch-over

- **Seed-first feature rule.** `hlasm.hlasm` may use a new hlasm feature
  only after a committed seed `hlasm.s` implements that feature.
  1. Implement the feature using only features the seed already has.
  2. Regenerate and commit the seed (gate C).
  3. Only then use the feature in the source.
- **The generated `hlasm.s` is never edited by hand.** Fixes go into
  `src/` and are followed by `just selfhost`.
- **Determinism.** Output must depend only on the input. No addresses,
  counters, or timestamps may leak into the text, or the fixed point breaks.

## Risks

- **Run time.** Each self-host run is ~10^8 instructions or more. Measure
  emulator wall time early in phase 2, and budget it the way plsw does.
- **Stack.** The 3 KB EBR stack may be too small for deep include and macro
  nesting at full scale. Watch for this in phase 2; the fallback is an SRAM
  stack (see `docs/bootstrap.md`).
- **Snapshot region size.** The relaxation pass snapshots
  `[_const_A, _line_is_keyword)` and `[_id_buf, _image_end)` into fixed
  1 KB-offset slots at 0x0D0000. Splitting and macro-izing the code can
  reorder or grow those regions. Add a size check (as an assembly-time
  `.org`/assert or a runtime check) before phase 2.
- **Gate B coverage.** Gate B is only as strong as the reg-rs suite.
  Phase 4 may need a few more targeted tests for paths that no demo
  exercises today.
