Step 4: Line reader and passthrough

Implement line-by-line reading and passthrough mode. Non-structured lines
are emitted to UART output unchanged as plain COR24 assembly.

Requirements:
- _read_line: read one line from source buffer into a line buffer,
  return line length in r0, return 0 on EOF
- _emit_line: write line buffer contents to UART
- _is_structured: check if current line starts with a keyword
  (MACRO, IF, DO, SELECT, SET, IFDEF, etc.)
- Main loop: read line, if not structured, emit it unchanged;
  if structured, skip it for now (future steps will process it)
- Handle comment-only lines (pass through)
- Handle label-only lines (pass through)
- Handle empty lines (pass through)

Test: load a small .s program as source, verify it is emitted unchanged.

Create reg-rs tests:
- hlasm_s4_passthrough_simple: load "nop\nhalt:\n bra halt\n", verify output
- hlasm_s4_passthrough_comments: load lines with ; comments, verify passthrough
- hlasm_s4_passthrough_skip_keywords: load "MACRO foo\nMEND\nnop\n",
  verify only "nop" is emitted

Context: docs/architecture.md, docs/design.md, docs/plan.md
Reference: ../sw-cor24-rpg-ii/rpg2.s for subroutine patterns

Do NOT use Python, C, Rust, awk, or sed. Only shell scripts and .s files.