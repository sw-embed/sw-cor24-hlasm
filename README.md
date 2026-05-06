# sw-cor24-hlasm -- HLASM-Inspired Macro-Assembler for COR24

An IBM HLASM-inspired macro-assembler for the COR24 24-bit RISC ISA,
written entirely in COR24 assembly. Reads HLASM-inspired structured
source and produces plain COR24 assembly output via UART.

Part of the [COR24 ecosystem](https://github.com/sw-embed/sw-cor24-project).

## Features (Planned)

- Structured control flow: IF/ELSEIF/ELSE/ENDIF, DO/ENDDO, SELECT/ENDSEL
- Real macros with parameters, defaults, and local labels
- Conditional assembly: IFDEF, IFEQ, SET symbols
- Plain assembly passthrough

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
cor24-run --assemble --run
```

## Prerequisites

- `cor24-run` -- build from [sw-cor24-emulator](https://github.com/sw-embed/sw-cor24-emulator)
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

# Or use shell scripts directly:
./build.sh          # build / test / run
./demo.sh           # demo / test / repl
```

## Project Structure

```
hlasm.s        -- COR24 assembly source (the macro-assembler)
bootstrap/     -- reduced self-hosting subset sources and proof points
build.sh       -- build / test / run script
demo.sh        -- demo script
justfile       -- just targets
docs/          -- architecture, prd, design, plan
reg-rs/        -- reg-rs test specifications and baselines
```

## Documentation

- [Architecture](docs/architecture.md) -- system overview and memory layout
- [Bootstrap Plan](docs/bootstrap.md) -- staged self-hosting path and blockers
- [PRD](docs/prd.md) -- product requirements and scope
- [Design](docs/design.md) -- syntax, lowering rules, data structures
- [Plan](docs/plan.md) -- step-by-step implementation roadmap

## Related Repositories

- [sw-cor24-emulator](https://github.com/sw-embed/sw-cor24-emulator) -- COR24 emulator + assembler
- [sw-cor24-forth](https://github.com/sw-embed/sw-cor24-forth) -- Forth for COR24
- [sw-cor24-rpg-ii](https://github.com/sw-embed/sw-cor24-rpg-ii) -- RPG-II for COR24
- [sw-cor24-project](https://github.com/sw-embed/sw-cor24-project) -- ecosystem hub

## Copyright

Copyright (c) 2026 Michael A. Wright

## License

MIT License. See [LICENSE](LICENSE) for the full text.
