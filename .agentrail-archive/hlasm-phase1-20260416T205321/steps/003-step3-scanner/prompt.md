Step 3: Scanner / tokenizer

Implement a scanner that reads characters from the source buffer and
produces tokens in memory.

Requirements:
- Token types (numeric codes stored in a token struct):
  TOK_EOF (0), TOK_NEWLINE (1), TOK_KEYWORD (2), TOK_MNEMONIC (3),
  TOK_REGISTER (4), TOK_NUMBER (5), TOK_IDENT (6), TOK_LABEL (7),
  TOK_COMMENT (8), TOK_COMMA (9), TOK_LPAREN (10), TOK_RPAREN (11),
  TOK_BACKSLASH (12)
- _next_token: read next token from source, store in token struct
- _scan_ident: read identifier (alphanumeric + underscore)
- _scan_number: read decimal or hex number (0x prefix, or plain decimal)
- _is_keyword: check if identifier is a keyword (MACRO, MEND, IF, etc.)
- _is_mnemonic: check if identifier is a COR24 instruction mnemonic
- _is_register: check if identifier is a register name (r0-r2, fp, sp, z, iv, ir)
- Keywords to recognize: MACRO, MEND, IF, ELSEIF, ELSE, ENDIF, DO, DOEXIT,
  ITERATE, ENDDO, SELECT, WHEN, OTHERWISE, ENDSEL, SET, IFDEF, IFNDEF,
  IFEQ, IFNE, ELSEASM, ENDIFASM
- Condition specifiers: cc_eq, cc_ne, cc_lt, cc_lu, cc_zset, cc_zclr
- For testing: print token type and value to UART for each token scanned

Create reg-rs tests:
- hlasm_s3_scan_instructions: scan "nop\nadd r0,r1\n", verify token sequence
- hlasm_s3_scan_keywords: scan "MACRO PUSH reg\nMEND\n", verify keywords
- hlasm_s3_scan_numbers: scan "lc r0,42\nla r0,0xFF\n", verify numbers
- hlasm_s3_scan_labels: scan "loop:\nbra loop\n", verify label tokens

Context: docs/design.md, docs/plan.md
Reference: ../sw-cor24-emulator/src/assembler.rs for token patterns

Do NOT use Python, C, Rust, awk, or sed. Only shell scripts and .s files.