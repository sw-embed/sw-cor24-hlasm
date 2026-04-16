M2: Lexer + tokenizer

Build a lexer that tokenizes .hlasm input into a structured token stream.

Requirements:
- Token types: Keyword (MACRO, MEND, IF, ELSEIF, ELSE, ENDIF, DO, DOEXIT, ITERATE, ENDDO, SELECT, WHEN, OTHERWISE, ENDSEL, COPY, SET, IFDEF, IFNDEF, IFEQ, IFNE, ELSEASM, ENDIFASM), Mnemonic (add, sub, mov, lw, sw, bra, etc.), Register (r0, r1, r2, fp, sp, z, iv, ir), Number (decimal, hex 0x/0FFh/#x), String (quoted), Label (name:), Ident (symbol names), Comment, Comma, LParen, RParen, Newline, EOF
- Recognize register names: r0, r1, r2, fp, sp, z, c, ir, iv
- Recognize condition specifiers: cc_eq, cc_ne, cc_lt, cc_lu, cc_zset, cc_zclr
- Handle parameter references: \name, \@ (macro-local label marker)
- Handle semicolon and hash comments
- Handle comma separators
- Handle parenthesized operands: (r0), offset(r0)
- Handle all number formats: decimal, 0x hex, 0FFh Intel hex, #x as24 hex

Refactor src/main.rs into src/lib.rs with modules:
- src/lib.rs -- crate root
- src/lexer.rs -- token types and lexer
- src/main.rs -- CLI entry point using library

Create reg-rs tests:
- hlasm_m2_tokenize_instructions -- tokenizes plain instructions
- hlasm_m2_tokenize_labels -- tokenizes labels
- hlasm_m2_tokenize_numbers -- tokenizes decimal, hex formats
- hlasm_m2_tokenize_keywords -- tokenizes IF, MACRO, etc.
- hlasm_m2_tokenize_params -- tokenizes \name and \@ references
- hlasm_m2_tokenize_comments -- handles ; and # comments

Tests should run hlasm with a token dump mode (add -t flag temporarily or use listing mode) and verify token output.

Context files: docs/design.md, docs/plan.md
Reference: ../sw-cor24-emulator/src/assembler.rs for tokenizer patterns

Do NOT use Python, C, or other HLL. Use only Rust and shell scripts.