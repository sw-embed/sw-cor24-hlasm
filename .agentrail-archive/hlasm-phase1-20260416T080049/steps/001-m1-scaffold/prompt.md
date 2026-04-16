M1: Project scaffold + passthrough

Create the Rust binary crate "hlasm" that reads .hlasm source from stdin or a file argument and writes plain .s output to stdout (or -o file).

Requirements:
- Cargo project: Cargo.toml with binary "hlasm", edition 2021+, no external dependencies (use only std)
- CLI args: -o <file.s>, -l (listing mode stub), -I <dir> (include path), -D <name[=val]>, --help, --version
- Read .hlasm source line by line
- Pass non-structured lines through to output unchanged
- Add source mapping comments: "; [hlasm src:N] ..." before each output line
- Support "; " and "#" comment lines (pass through)
- Support label lines (pass through)
- Support empty lines (pass through)

Files to create:
- Cargo.toml
- src/main.rs (minimal: read args, read input, write output)

Also create:
- scripts/build.sh (cargo build --release wrapper)
- scripts/test.sh (reg-rs run -p hlasm --parallel)

Create first reg-rs test:
- reg-rs/hlasm_m1_passthrough.rgt -- echo "nop" | hlasm should output "nop"
- Establish golden baseline

Context files: docs/architecture.md, docs/prd.md, docs/design.md, docs/plan.md
Reference: ../sw-cor24-forth for reg-rs test patterns, ../sw-cor24-emulator for COR24 assembler

Do NOT use Python, C, or other HLL. Use only Rust and shell scripts.