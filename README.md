# sw-cor24-hlasm -- HLASM-Inspired Macro-Assembler for COR24

An IBM HLASM-inspired macro-assembler for the COR24 24-bit RISC ISA,
written entirely in COR24 assembly. Reads HLASM-inspired structured
source and produces plain COR24 assembly output via UART.

Part of the [COR24 ecosystem](https://github.com/sw-embed/sw-cor24-project).

## Features

**How to use it: [docs/user-guide.md](docs/user-guide.md)** (setup, running,
every feature with examples, limits and error messages).

- Named constants and expressions: `EQU`, `SET`, `* / % << >> & | ^ ~ ( )`,
  character literals; values are substituted into instruction and data
  operands (cor24-asm has no EQU)
- Macros with named, positional, default and keyword parameters and `\@`
  local labels; macros can call macros (8 deep, recursion allowed), and
  bodies can use conditional assembly, structured statements and
  `&SYSNARG` (argument count)
- Conditional assembly: `IFDEF`, `IFNDEF`, `IFEQ`, `IFNE`, `ELSEASM`, and
  `IFSAME`/`IFDIFF` text tests so a macro can tell a register argument from
  a constant or label
- Structured control flow: IF/ELSEIF/ELSE/ENDIF, DO/DOEXIT/ITERATE/ENDDO,
  SELECT/WHEN/OTHERWISE/ENDSEL, with automatic long-range jumps; conditions
  `cc_eq`, `cc_ne`, `cc_lt`, `cc_le`, `cc_gt`, `cc_ge` and unsigned
  `cc_lu`, `cc_leu`, `cc_gtu`, `cc_geu`, joined with `AND` or `OR`
  (short-circuit, like C's `&&` and `||`)
- Record layouts: `DSECT`/`USECT`/`FIELD`/`DEND` (library macros) define
  struct and union field offsets and sizes; `ERROR 'message'` lets macros
  reject bad arguments
- Data conveniences: `.ascii`, `.asciz` (with `\xNN` escapes), `.space`,
  `.fill`
- Multi-file sources: `INCLUDE` / `COPY` members through source sets (32
  members, 15-character names, nesting 16)
- Optional annotations, listing, cross-reference and diagnostics
- Plain assembly passthrough; checked limits that stop with `ERROR:`
- Errors name the member and line: `ERROR: <member>:<line>: <message>`
- One-command end-to-end runs: `scripts/hlasm-e2e.sh prog.hlasm` (hlasm,
  then cor24-asm, then cor24-emu) prints the program's output

## Status

Done:

- All the features above, each with demos and regression tests
  (`./build.sh test`, 131 tests).
- Every limit in [docs/limits-and-lifting-plan.md](docs/limits-and-lifting-plan.md)
  that was scheduled has been lifted: 512 symbols, 256 macros, 64 KB of macro
  bodies, 32-deep nesting, 32 source members.
- Structured statements assemble at any branch distance
  ([docs/structured-jump-relaxation.md](docs/structured-jump-relaxation.md)).
- All prerequisites for writing hlasm in HLASM itself are met
  ([docs/bootstrap-hlasm.md](docs/bootstrap-hlasm.md)).

**The tiny-C demos in HLASM.** 42 example programs of the tc24r C compiler
(`../sw-cor24-x-tinyc/demos`) are rewritten in HLASM on a shared macro
library (`lib/`), in `demos/tinyc/`, each with a regression test. Run them
with `./demo.sh c-demos`.
[docs/c-demos-in-hlasm.md](docs/c-demos-in-hlasm.md) shows every port next to
its C source, documents every macro, and compares each port with tc24r's
compiled version. Across the 38 demos with both versions:

- the hlasm programs are 41% of tc24r's code size;
- 32 of the 38 run fewer instructions;
- of the other six, five divide (the library's divide is correct for
  negative operands and tc24r's is not, and slower), and demo9 waits for an
  interrupt in both.

[docs/tinyc-port-plan.md](docs/tinyc-port-plan.md) has the survey and the
port plan.

Not implemented yet:

- A sw-tos target for the system-services macros, so the same programs run
  under sw-tos. Planned in [docs/svc-swtos-plan.md](docs/svc-swtos-plan.md).
  Only the bare-metal target exists.
- hlasm written in HLASM, reaching a fixed point. Planned in
  [docs/bootstrap-hlasm.md](docs/bootstrap-hlasm.md); every prerequisite is
  met, but the work has not started.

## Opt-in Source Switches

All four are off by default and activated by a `SET <name>,1` line anywhere in the source:

- `SET HLANN,1` -- annotate structured control-flow lowering with `; HLASM ...` comments
- `SET HLIST,1` -- emit listing comments for COPY members, macro definitions, macro expansions, and selected consumed directives
- `SET HLXREF,1` -- emit a compact end-of-run cross-reference section
- `SET HLDIAG,1` -- activate the diagnostic channel (`; !! hlasm: <msg> at src<id>:<line>`)

## Pipeline

```
.hlasm source (in memory)
     |
     v
hlasm.s (macro-assembler running on COR24)
     |
     v
UART output: plain .s assembly
     |
     v
cor24-asm out.s -o out.lgo; cor24-emu --lgo out.lgo
```

## Prerequisites

- `cor24-asm` -- build from [sw-cor24-x-assembler](https://github.com/sw-embed/sw-cor24-x-assembler)
- `cor24-emu` -- build from [sw-cor24-emulator](https://github.com/sw-embed/sw-cor24-emulator)
  (`scripts/run-kernel.sh` finds both on PATH, via `COR24_ASM` / `COR24_EMU`,
  or in sibling checkouts' `target/release`)
- `reg-rs` -- for running tests

## Quick Start

```bash
# Build / assemble check
just build

# Run demo
just demo

# Run tests
just test

# Run the split bootstrap proof
just bootstrap

# Run an HLASM program end to end (hlasm -> cor24-asm -> cor24-emu)
scripts/hlasm-e2e.sh demos/d42_macro_layering.hlasm

# Run the tiny-C demos ported to HLASM
./demo.sh c-demos

# Or use shell scripts directly:
./build.sh          # build / test / run
./demo.sh           # demo / test / repl
```

## Project Structure

```
hlasm.s        -- COR24 assembly source (the macro-assembler)
bootstrap/     -- reduced self-hosting subset sources and proof points
build.sh       -- build / test / run script
scripts/       -- run-kernel.sh: assemble a .s (cor24-asm) and run it (cor24-emu);
                  hlasm-e2e.sh: .hlasm -> hlasm -> cor24-asm -> cor24-emu, prints UART output
demo.sh        -- demo script
demos/         -- demo programs (d01-d45), libtest/ (macro library tests)
lib/           -- the macro library (COPY members; see docs/c-demos-in-hlasm.md)
justfile       -- just targets
docs/          -- user guide, architecture, plans
reg-rs/        -- reg-rs test specifications and baselines
```

## Documentation

- [User Guide](docs/user-guide.md) -- setup, running, every feature, limits
- [C Demos in HLASM](docs/c-demos-in-hlasm.md) -- the tiny-C example programs
  ported to HLASM, and the macro library they use
- [Tiny-C Port Plan](docs/tinyc-port-plan.md) -- survey of the C demos, macro
  catalog, port order, feature gaps
- [Limits and Lifting Plan](docs/limits-and-lifting-plan.md) -- every limit,
  defect and language gap, and when each was fixed
- [Architecture](docs/architecture.md) -- system overview and memory layout
- [Bootstrap Plan](docs/bootstrap.md) -- staged self-hosting path and blockers
- [hlasm in HLASM](docs/bootstrap-hlasm.md) -- plan for rewriting hlasm in its
  own language
- [sw-tos services target](docs/svc-swtos-plan.md) -- plan for running the same
  HLASM programs under sw-tos
- [PRD](docs/prd.md) -- product requirements and scope
- [Design](docs/design.md) -- syntax, lowering rules, data structures
- [Plan](docs/plan.md) -- the original (phase 1) implementation roadmap

## Related Repositories

- [sw-cor24-emulator](https://github.com/sw-embed/sw-cor24-emulator) -- COR24 emulator (`cor24-emu`)
- [sw-cor24-x-assembler](https://github.com/sw-embed/sw-cor24-x-assembler) -- COR24 cross-assembler (`cor24-asm`)
- [sw-cor24-forth](https://github.com/sw-embed/sw-cor24-forth) -- Forth for COR24
- [sw-cor24-rpg-ii](https://github.com/sw-embed/sw-cor24-rpg-ii) -- RPG-II for COR24
- [sw-cor24-project](https://github.com/sw-embed/sw-cor24-project) -- ecosystem hub

## Copyright

Copyright (c) 2026 Michael A. Wright

## License

MIT License. See [LICENSE](LICENSE) for the full text.
