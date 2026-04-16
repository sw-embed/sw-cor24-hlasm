Step 2: Source buffer reader

Implement subroutines to read characters from an in-memory source buffer.
The source buffer will hold .hlasm input text loaded via --load-binary.

Requirements:
- Source buffer descriptor layout (same pattern as _deck_desc in rpg2.s):
  +0: base address (24-bit)
  +3: length (24-bit)
  +6: current position (24-bit)
- _read_char: read next char from source buffer, return in r0, return 0 on EOF
- _peek_char: read current char without advancing position
- _skip_whitespace: advance past spaces and tabs
- _skip_to_eol: advance to end of current line
- _at_eol: check if current position is at newline or EOF
- _advance_char: move position forward by 1

Test with --load-binary: prepare a small text file, load at 0x080000,
set up descriptor, read and echo characters to UART.

Create reg-rs tests:
- hlasm_s2_read_chars: load "Hello", echo each char, verify UART output
- hlasm_s2_eof: load short text, read past end, verify halt behavior

Context: docs/architecture.md, docs/design.md, docs/plan.md
Reference: ../sw-cor24-rpg-ii/rpg2.s _read_record for buffer descriptor pattern

Do NOT use Python, C, Rust, awk, or sed. Only shell scripts and .s files.