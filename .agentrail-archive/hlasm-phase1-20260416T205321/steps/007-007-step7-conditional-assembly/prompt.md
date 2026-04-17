Step 7: Conditional assembly (SET, IFDEF, IFEQ)

Implement SET symbol definition and lookup. Evaluate IFDEF/IFNDEF (symbol defined/not defined) and IFEQ/IFNE (integer comparison). Skip or include sections based on conditions.

Requirements:
- _symbol_table: fixed-size array of symbol descriptors (name ptr, value)
- _set_symbol: parse 'SET name,value' line, store in symbol table
- _lookup_symbol: check if a name is defined, return value
- On IFDEF line: if symbol defined, include lines until ENDIFASM; otherwise skip
- On IFNDEF line: opposite of IFDEF
- On IFEQ line: parse 'IFEQ name,value', compare symbol value with literal
- On IFNE line: opposite of IFEQ
- ELSEASM: toggle inclusion within a conditional block
- ENDIFASM: end conditional block
- _cond_state: 0=including, 1=skipping, 2=skipped (already included ELSEASM)
- Max 16 symbols, max 64 bytes total symbol name storage

Test: load 'SET DEBUG,1\nIFDEF DEBUG\n nop\nENDIFASM\nSET DEBUG,0\nIFDEF DEBUG\n add r0,1\nENDIFASM\n', verify output is 'nop\r\n' (second block skipped because DEBUG=0).

Also test IFEQ: 'SET VER,3\nIFEQ VER,3\n nop\nENDIFASM\nIFEQ VER,2\n add r0,1\nENDIFASM\n', verify output is 'nop\r\n'.

Context: docs/architecture.md, docs/design.md, docs/plan.md
Reference: hlasm.s (existing macro expansion from step 6), ../sw-cor24-rpg-ii/rpg2.s for subroutine patterns

Do NOT use Python, C, Rust, awk, or sed. Only shell scripts and .s files.