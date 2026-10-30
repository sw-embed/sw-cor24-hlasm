Goal: port the tiny-C (tc24r) example programs in ../sw-cor24-x-tinyc/demos to hlasm source, using macros where they make sense, so the repo demonstrates the value of hlasm macros: a shared macro library (COPY members) used across many examples, each example running end to end (hlasm -> .s -> cor24-asm -> cor24-emu) with checked UART output, and a side-by-side showcase against the C source and tc24r's generated .s.

Prerequisite: structured IF/DO/SELECT output must assemble. Step 1 implements docs/structured-jump-relaxation.md (bra when in range, else push/pop r2 around la/jmp with a target trampoline; two-pass sizing).

Constraints: this is a .s project -- hlasm.s plus shell scripts and .hlasm sources only (no Rust/C/Python/awk). Tools: scripts/run-kernel.sh (cor24-asm + cor24-emu). Keep ./build.sh test green; every new example gets a reg-rs test. When a needed macro feature is missing (e.g. structured keywords or conditional assembly inside macro bodies, default parameter values), insert a step to add it to hlasm rather than working around it silently.

The paused saga hlasm-diagnostics-and-branch-relax (archived 2026-10-30, steps 6-9 pending: diag-structured-block-health, branch-relax-pseudos, diag-branch-distance-warning, rpg2-unblock-proof) should be resumed afterwards.
