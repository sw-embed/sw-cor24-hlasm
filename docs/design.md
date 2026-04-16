# Design Document

## Syntax Design

### Source File Extension

`.hlasm` -- HLASM-inspired COR24 structured macro-assembly source.

### Pass Structure

The tool processes source in these passes:

1. **Lex**: Tokenize input into a stream of tokens
2. **Parse**: Identify macro definitions, structured blocks, conditionals,
   COPY directives, and plain assembly lines
3. **Expand**: Resolve COPY, expand macro invocations, generate unique labels
4. **Condition**: Evaluate conditional assembly (SET, IFDEF, IFEQ)
5. **Lower**: Transform structured blocks (IF, DO, SELECT) into labels + branches
6. **Emit**: Write plain .s output with source mapping comments

### Structured Control-Flow Syntax

#### IF / ELSEIF / ELSE / ENDIF

```
IF cc_eq, r0, 0
    ; body when r0 == 0
ELSEIF cc_lt, r1, 10
    ; body when r0 != 0 and r1 < 10
ELSE
    ; body otherwise
ENDIF
```

Condition specifiers: `cc_eq`, `cc_ne`, `cc_lt` (signed), `cc_lu` (unsigned),
`cc_ge`, `cc_le`, `cc_gt`, `cc_zset` (C flag set), `cc_zclr` (C flag clear).

Lowering for IF/ELSE/ELSEIF/ENDIF:

```
; IF cc_eq, r0, 0
    ceq r0, z
    brf .L0001_if_end
    ; body
; ELSEIF cc_lt, r1, 10
    bra .L0002_if_elseif
.L0001_if_end:
    cls r1, z
    brf .L0003_if_else
    lc r0, 10
    cls r1, r0
    ; elseif body
    bra .L0004_if_done
.L0002_if_elseif:
.L0003_if_else:
    ; else body
.L0004_if_done:
; ENDIF
```

Note: For non-zero comparisons, the constant is loaded into a register
using `lc` (range 0..127) or `la` + `lw` (larger values), and compared
against that register. This respects the COR24 constraint that `ceq/cls/clu`
only work with registers.

#### DO / DOEXIT / ITERATE / ENDDO

```
DO
    ; body (infinite loop)
    DOEXIT cc_eq, r0, 0
    ; more body
ENDDO

DO WHILE, cc_ne, r0, 0
    ; body
ENDDO
```

Lowering for infinite DO:

```
.L0001_do_top:
    ; body
    ceq r0, z
    brt .L0002_do_exit
    ; more body
    bra .L0001_do_top
.L0002_do_exit:
```

Lowering for DO WHILE:

```
.L0001_do_cond:
    ; evaluate condition
    brf .L0002_do_exit
    ; body
    bra .L0001_do_cond
.L0002_do_exit:
```

ITERATE jumps to the condition/loop top. DOEXIT jumps past ENDDO.

#### SELECT / WHEN / OTHERWISE / ENDSEL

```
SELECT r0
    WHEN 0
        ; handle case 0
    WHEN 1
        ; handle case 1
    OTHERWISE
        ; default
ENDSEL
```

Lowering:

```
    ceq r0, z
    brt .L0001_sel_0
    lc r1, 1
    ceq r0, r1
    brt .L0002_sel_1
    bra .L0003_sel_other
.L0001_sel_0:
    ; case 0 body
    bra .L0004_sel_done
.L0002_sel_1:
    ; case 1 body
    bra .L0004_sel_done
.L0003_sel_other:
    ; otherwise body
.L0004_sel_done:
```

### Macro Syntax

#### MACRO / MEND

```
PUSHREG MACRO reg
    push \reg
MEND
```

Parameters referenced with backslash prefix: `\reg`, `\dst`, `\src`.

#### Default and keyword parameters

```
EMIT_CHAR MACRO ch=65
    la r2, -65280
    lc r0, \ch
poll\@: lb r1, 1(r2)
    cls r1, z
    brt poll\@
    sb r0, 0(r2)
MEND
```

`\@` generates a unique local label per expansion (e.g., `poll0001`, `poll0002`).

#### Invoking macros

```
    PUSHREG r0
    PUSHREG r1
    EMIT_CHAR
    EMIT_CHAR ch=66
```

### Conditional Assembly Syntax

```
SET DEBUG, 1
SET VERSION, 3
SET UART_BASE, -65280

IFDEF DEBUG
    ; debug-only code
ENDIF

IFNDEF RELEASE
    COPY debug_helpers.hlasm
ENDIF

IFEQ VERSION, 3
    ; version 3 specific code
ELSEASM
    ; other versions
ENDIFASM
```

SET symbols are integers. String SET is not in initial scope.

### COPY / Include

```
COPY uart_macros.hlasm
COPY "path/to/file.hlasm"
```

Search order:
1. Relative to including file's directory
2. `lib/` directory in project root
3. Paths specified via `-I` command-line flag

### Plain Assembly Passthrough

Any line that is not a macro definition, structured block, conditional, or
COPY directive is passed through to the output as-is. This includes:

- All standard COR24 instructions: add, sub, mov, lw, sw, bra, etc.
- Labels: `label_name:` (on their own line)
- Directives: .byte, .word, .comm, .org, .text, .data
- Comments: `;` and `#`

### Source Mapping Comments

Output .s includes comments mapping back to .hlasm source:

```
; [hlasm src:3] IF cc_eq, r0, 0
    ceq r0, z
    brf .L0001
; [hlasm src:4]     push r0
    push r0
; [hlasm src:5] ENDIF
```

## Label Generation

- Global labels: passed through as-is
- Macro-local labels: `<name>\@` becomes `<name><expansion_counter>`
  (e.g., `loop\@` in expansion 5 becomes `loop0005`)
- Structured block labels: `.L<counter>_<type>_<qualifier>`
  (e.g., `.L0001_if_end`, `.L0002_do_top`, `.L0003_sel_1`)

Counter is global per assembly, incrementing monotonically.

## Condition Specifier Semantics

The COR24 ISA has a single C flag set by compare instructions. The condition
specifiers map as follows:

| Specifier | COR24 Instructions | Semantics |
|-----------|-------------------|-----------|
| `cc_eq` | `ceq ra, rb` | C set if ra == rb |
| `cc_ne` | `ceq ra, rb` | C clear if ra != rb (invert branch sense) |
| `cc_lt` | `cls ra, rb` | C set if ra < rb (signed) |
| `cc_lu` | `clu ra, rb` | C set if ra < rb (unsigned) |
| `cc_zset` | (no compare) | C flag already set |
| `cc_zclr` | (no compare) | C flag already clear |

For comparisons with constants, the constant is loaded into a register first:
- 0..127: `lc r_tmp, const`
- 0..255: `lcu r_tmp, const`
- larger: `la r_tmp, const` (4 bytes)

This respects the COR24 constraint that compare instructions only take registers.

## Command-Line Interface

```
hlasm [OPTIONS] <input.hlasm>

OPTIONS:
  -o <file.s>        Output file (default: stdout)
  -l                 Listing mode (macro expansion + lowered output)
  -I <dir>           Add include search path (repeatable)
  -D <name[=val]>    Define SET symbol (repeatable)
  --help             Show help
  --version          Show version
```

## Error Handling

Errors are reported with .hlasm source line number and context:

- Undefined macro invocation
- Wrong number of macro arguments
- Undefined SET symbol in conditional
- Malformed structured block (missing ENDIF, ENDDO, etc.)
- COPY file not found
- Nested macro expansion depth exceeded

Errors halt assembly and produce a non-zero exit code. Warnings produce
messages but continue.

## Implementation Language

Rust. Single binary crate. No workspace. No Python, C, or other HLL.

Build: `cargo build --release` (or a shell script wrapper)
Install: `cargo install --path .` or copy binary

## Testing Approach

Tests use reg-rs golden-output regression testing (same as sw-cor24-forth):

- Test prefix: `hlasm_`
- Each test runs the hlasm tool and pipes output through cor24-run
- Preprocess filter extracts relevant output (UART output, listing sections)
- Test files in `reg-rs/` directory with `.rgt` and `.out` pairs

Test categories:
1. **Lowering tests**: .hlasm -> .s, verify output matches expected assembly
2. **Macro tests**: verify expansion correctness
3. **Conditional tests**: verify IFDEF/IFEQ behavior
4. **End-to-end tests**: .hlasm -> .s -> cor24-run -> verify UART output
