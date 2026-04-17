Step 5: Macro table

Implement a macro table to store macro definitions. When a MACRO line is encountered, begin recording subsequent lines into the macro table until MEND is found. When a macro invocation (identifier matching a defined macro name) is encountered, look it up and begin expansion.

Requirements:
- _macro_table: fixed-size array of macro descriptors (name ptr, body ptr, body length)
- _macro_buf: buffer to store macro bodies (concatenated, with null terminators)
- On MACRO line: extract macro name, start recording body
- On MEND line: stop recording, store in macro table
- _lookup_macro: check if an identifier matches any macro name
- Max 16 macros, max 1024 bytes total macro body storage

Test: load 'MACRO inc\n add r0,1\nMEND\ninc\ninc\n', verify output is 'add r0,1\r\nadd r0,1\r\n'

Context: docs/architecture.md, docs/design.md, docs/plan.md
Reference: ../sw-cor24-rpg-ii/rpg2.s for subroutine patterns

Do NOT use Python, C, Rust, awk, or sed. Only shell scripts and .s files.