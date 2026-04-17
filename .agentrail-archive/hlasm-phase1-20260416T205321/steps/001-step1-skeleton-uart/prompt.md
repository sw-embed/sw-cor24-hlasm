Step 1: Skeleton and UART output

Create the initial hlasm.s with reset vector, UART emit subroutines, and a halt loop.
Follow the exact patterns from ../sw-cor24-rpg-ii/rpg2.s.

Requirements:
- hlasm.s with _main entry point
- push fp / mov fp,sp at entry
- _emit_char subroutine: write one byte to UART (0xFF0100) with TX busy-wait
- _emit_crlf subroutine: print CR+LF
- Print "HLASM" to UART
- Halt loop (bra to self)
- Follow sw-cor24-rpg-ii calling convention

Also create:
- build.sh (following ../sw-cor24-rpg-ii/build.sh pattern exactly)
- demo.sh (following ../sw-cor24-rpg-ii/demo.sh pattern exactly)
- Makefile (following ../sw-cor24-rpg-ii/Makefile pattern exactly)

Create first reg-rs test:
- reg-rs/hlasm_s1_hello.rgt: cor24-run --run hlasm.s --speed 0 -n 1000, preprocess="grep -A 100 UART output:", exit_code=0, desc="Skeleton prints HLASM"
- Establish golden baseline with reg-rs create then verify with reg-rs run

Context: docs/architecture.md, docs/design.md, docs/plan.md
Reference: ../sw-cor24-rpg-ii/rpg2.s for exact patterns
Reference: ../sw-cor24-forth/forth.s for UART I/O patterns

Do NOT use Python, C, Rust, awk, or sed. Only shell scripts and .s files.