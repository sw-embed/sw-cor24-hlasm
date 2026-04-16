M3: MACRO/MEND + expansion

Implement macro definition, invocation, and expansion.

Requirements:
- MACRO <name> [param1 [=default], param2, ...] -- begin macro definition
- MEND -- end macro definition
- Macro body tokens are collected but not expanded until invocation
- Invocation: <name> [arg1, arg2, ...] or <name> key1=val1, key2=val2
- Parameter substitution: \param_name replaced with argument value
- Default parameters: if not provided, use default value
- Local labels: \@ replaced with unique counter (e.g., loop0001, loop0002)
- Each macro expansion increments the global label counter
- Nested macro calls: macro body can invoke other macros
- Recursive macros allowed (with depth limit, e.g., 64)
- Macro invocation can appear anywhere a mnemonic can appear

New modules:
- src/macro.rs -- macro definition, parameter binding, expansion

Refactor processing pipeline:
1. First pass: collect all MACRO/MEND definitions (store in HashMap)
2. Second pass: expand macro invocations, substitute parameters, generate local labels
3. Output: expanded lines with source mapping comments

Create reg-rs tests:
- hlasm_m3_macro_simple -- define and invoke a simple macro
- hlasm_m3_macro_params -- positional parameter substitution
- hlasm_m3_macro_defaults -- default parameter values
- hlasm_m3_macro_local_labels -- \@ generates unique labels, no collisions
- hlasm_m3_macro_nested -- macro body invokes another macro
- hlasm_m3_macro_multiple_invocations -- same macro invoked multiple times
- hlasm_m3_macro_keyword_args -- keyword argument invocation
- hlasm_m3_end_to_end -- define macro, use it in code, pipe through cor24-run

Context files: docs/design.md, docs/plan.md
Reference: ../sw-cor24-forth/forth.s for COR24 assembly patterns
Reference: ../sw-cor24-emulator/src/assembler.rs for encoding

Do NOT use Python, C, or other HLL. Use only Rust and shell scripts.