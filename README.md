# sw-cor24-hlasm -- HLASM-Inspired Macro-Assembler for COR24

A structured macro-assembler front-end for the COR24 24-bit RISC ISA,
inspired by IBM HLASM. Reads `.hlasm` source and lowers structured
control-flow and macro constructs into plain COR24 assembly (`.s` files)
compatible with `cor24-run`.

Part of the [COR24 ecosystem](https://github.com/sw-embed/sw-cor24-project).

## Features (Planned)

- Structured control flow: IF/ELSEIF/ELSE/ENDIF, DO/ENDDO, SELECT/ENDSEL
- Real macros with parameters, defaults, and local labels
- Conditional assembly: IFDEF, IFEQ, SET symbols
- COPY/include for reusable macro libraries
- Source mapping comments for debugging
- Listing mode with macro expansion trace

## Pipeline

```
.hlasm source --> hlasm tool --> plain .s --> cor24-run (assemble + execute)
```

## Prerequisites

- Rust (1.75+)
- `cor24-run` -- build from [sw-cor24-emulator](https://github.com/sw-embed/sw-cor24-emulator)
- `reg-rs` -- for running tests

## Quick Start (when implemented)

```bash
# Build
scripts/build.sh

# Run
echo 'nop' | cargo run
hlasm input.hlasm -o output.s

# End-to-end
hlasm input.hlasm | cor24-run --run /dev/stdin --dump --speed 0

# Run tests
scripts/test.sh
```

## Project Structure

```
docs/          -- architecture, prd, design, plan
reg-rs/        -- reg-rs test specifications and baselines
scripts/       -- build and test scripts
src/           -- Rust source
tests/         -- test .hlasm source files
lib/           -- standard macro library
examples/      -- example .hlasm programs
```

## Documentation

- [Architecture](docs/architecture.md) -- system overview and component design
- [PRD](docs/prd.md) -- product requirements and user stories
- [Design](docs/design.md) -- syntax, lowering rules, CLI interface
- [Plan](docs/plan.md) -- milestones and implementation roadmap

## Related Repositories

- [sw-cor24-emulator](https://github.com/sw-embed/sw-cor24-emulator) -- COR24 emulator + assembler
- [sw-cor24-forth](https://github.com/sw-embed/sw-cor24-forth) -- Forth for COR24
- [sw-cor24-project](https://github.com/sw-embed/sw-cor24-project) -- ecosystem hub

## Copyright

Copyright (c) 2026 Michael A. Wright

## License

MIT License. See [LICENSE](LICENSE) for the full text.
