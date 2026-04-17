Step 6: Macro expansion

Implement macro invocation: look up macro in table, substitute parameters, generate unique local labels for \@. Emit expanded body to output.

Requirements:
- _expand_macro: look up macro by name, get body pointer and length, emit each line
- _substitute_params: replace positional params (&1, &2, ...) in body lines with actual arguments
- Unique label counter for \@ substitution (e.g. L0001, L0002, ...)
- Parse macro invocation: identifier followed by argument list
- Arguments are comma-separated positional parameters
- When a line starts with an identifier matching a macro name, expand it instead of passing through

Test: define 'MACRO pushreg\n st &1\n st &2\nMEND\n', invoke 'pushreg r0,r1' twice, verify output is 'st r0\nst r1\nst r0\nst r1\n' (each invocation emits the body with params substituted).

Also test \@ substitution: 'MACRO loop\nL\@: add r0,1\n b L\@\nMEND\n', invoke 'loop' twice, verify labels are unique (L0001, L0001 for first; L0002, L0002 for second).

Context: docs/architecture.md, docs/design.md, docs/plan.md
Reference: hlasm.s (existing macro table from step 5), ../sw-cor24-rpg-ii/rpg2.s for subroutine patterns

Do NOT use Python, C, Rust, awk, or sed. Only shell scripts and .s files.