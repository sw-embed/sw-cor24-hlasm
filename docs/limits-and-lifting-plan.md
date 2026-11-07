# hlasm Limits and Lifting Plan

Status: audit complete (2026-10-31, tinyc-macro-ports saga step 2). Step 3
fixed D1-D3 and D7; step 4 lifted the table limits (see "Now" below); step 5
added M1 (EQU in operands), M4 (expressions) and D6 (string escapes);
step 6 added L10, M2 and M3 (macro layering) and fixed D5 and D12;
step 7 lifted L19-L21 (32 members, 15-char names, nesting 16) and added M7
(member:line in errors). The plan's scheduled lifts are all done; the
remaining items (M5, M6, cost) belong to later sagas (see "Schedule").

This document records every capacity limit and known defect in `hlasm.s`,
who needs it raised, and how to lift it. Its consumers are:

- the tiny-C ports in this saga (`docs/c-demos-in-hlasm.md`);
- the plsw migration off tiny-C (`../sw-cor24-plsw/docs/migrate-from-c-to-hlasm.md`,
  items B1-B7 and G1-G7);
- self-hosting (`docs/bootstrap-hlasm.md`).

## Headline findings

1. **No limit reports an error.** hlasm has no diagnostic for any overflow.
   Depending on the table, overflow is silent truncation, corruption of a
   neighbouring table, or a hang.
2. **The tables are toy-sized:**
   - 16 symbols, with names of at most 5 characters;
   - 32 macros;
   - **1,023 bytes of macro body for the whole program**.
   A macro library cannot fit.
3. **Symbol names of 6 or more characters silently fail.** The value
   overwrites the name's NUL terminator, so the lookup misses. d32
   (`HEXVAL`, `BINVAL`, `HEXSUF`) drops three conditional blocks, and its
   golden output records that as expected.
4. **SET values never reach the output.** SET only drives conditional
   assembly. cor24-asm has no `.equ` (verified: `la r0,X` gives "Undefined
   label"), so a named constant cannot be used in an instruction today.
5. **Several overflows hang rather than corrupt:**
   - 20 or more symbols;
   - 33 or more macros;
   - input lines of 175 characters or more;
   - an expanded line of 140 bytes or more (the rest of the source is
     swallowed).
6. **Structured label ids break at 1000**, about 333 IFs, because
   `_emit_dec24` prints 3 digits. `\@` breaks at 10,000 expansions.
7. **Memory is not the constraint.** About 489 KB of low SRAM
   (0x004D87-0x07EFFF) and about 236 KB above the arena are unused. The
   limits are the table sizes hard-coded in the arena, not the space
   available.

Step 4 addressed findings 1, 2, 3, 5 and 6: every table limit now stops
with an ERROR, the tables were resized (see "Now" in the limits table), and
`reg-rs/check_limits.sh` tests each limit. Finding 4 is step 5 (M1).

The audit's scratch tests are reproducible. Each is a `.hlasm` file run
through hlasm at a chosen size; they become regression tests when each lift
lands.

## Limits table

Key to the Check column (as audited, before step 4):
- "none": no bound check; overflow corrupts or hangs.
- "silent": checked, but the excess is dropped without a message.

"Now" gives the value after step 4 (capacity-tables-and-guards). Every
limit marked "ERROR" stops with an `ERROR: ...` line from `_fatal`, and
each has a reg-rs test (`hlasm_limit_*`) at the limit and one past it.

| # | Limit | Audited | Check | Overflow | Needed by | Now |
|---|---|---|---|---|---|---|
| L1 | Symbol entries | 16 x 9 B | none | 17-19 corrupt the cond stack; 20 or more hang | ports, plsw B1, self-host | **512, ERROR** |
| L2 | Symbol name length | 5 chars | none | lookup fails silently | everyone | **31 chars, ERROR** |
| L3 | Symbol value | 24-bit, wraps | - | wraps | - | unchanged (24-bit machine) |
| L4 | Macros | 32 x 39 B | none | 33 or more hang | macro library, plsw B1 | **256, ERROR** |
| L5 | Macro name | 31 chars | silent | rest dropped | - | **31 chars, ERROR** |
| L6 | Named params | 8, names of at most 8 chars | silent | dropped or mangled | library macros | **16 params, 31-char names, ERROR** |
| L7 | Positional params | `&1`-`&9` | - | missing argument gives empty | - | unchanged |
| L8 | Macro body pool | 1,023 B **total** | none | truncated; empty at about 1,160 B | macro library (fatal today) | **64 KB, ERROR** |
| L9 | Expansion buffer | 129 B | none | 132 B corrupts `\@`; 140 B or more swallows the rest of the source | long macro lines | **expanded lines up to 256 chars (1 KB buffer), ERROR** |
| L10 | Nested macro calls | not supported | - | inner call emitted raw | library layering (PUTS calls PUTC), plsw B5 | **8 calls deep (recursion allowed), ERROR**; 16 arguments per call, ERROR |
| L11 | `\@` counter | 0001-9999 | none | `L:000` (invalid label) | self-host | **4 digits zero-padded, wider past 9999** (unique; existing outputs unchanged) |
| L12 | Cond-asm stack | 8 x 3 B | none | overwrites the src-return stack; at 9 levels inside an INCLUDE the rest of the parent file is lost | plsw B3 | **32, ERROR** |
| L13 | IF / DO / SELECT depth | 8 each | silent | opener dropped, body emitted unconditionally | plsw B3 | **32 each, ERROR** |
| L14 | cc / lhs / rhs operand buffers | 16 B each | none | operands spill into each other; DO depth corrupted | long names | **260 B each (a whole line), cannot overflow** |
| L15 | Selector / WHEN buffers | 12 B (x8) | none | overflow into the EOF flag and param count | - | **256 B x 32 selectors, 260 B WHEN, cannot overflow** |
| L16 | Structured label id | 999 | none | `_hlif_:00_false`; cor24-asm rejects it | ports, self-host (B4) | **any 24-bit id** (`_emit_dec24` full range); tested to 1200 |
| L17 | Input line | nominal 128 B; arena space 165 B | **none** | 166 B garbage; 175 B or more hang | plsw G5 | **256 chars, ERROR** |
| L18 | Main buffer | 32,767 B default (docs say 4,096) | stops at length or NUL | truncated mid-line | self-host | documented (sourceset sets any length up to the 0x0BFFFF window) |
| L19 | Extra buffers / include slots | 3 (config block layout) | host-side only | - | macro library members, self-host | **32 members (new config layout), ERROR** in hlasm and in `make_cfg.sh` |
| L20 | Include name | 8 chars | host-side only | - | readable member names | **15 chars**; `make_cfg.sh` refuses longer names |
| L21 | Include nesting | 8 | silent | INCLUDE ignored | - | **16, ERROR** |
| L22 | HLXREF symbols / HLDIAG names | 16 x 16 B | silent | extras ignored | larger programs | **512 / 64 names of 31 chars** |
| L23 | XREF expand counts | 16 B (but 32 macros) | none | macros 17-32 corrupt `_xref_symbol_count`, even with HLXREF off | - | **256 x 3-byte counters** (bytes also wrapped at 256) |
| L24 | Relax tables | 1,024 ids or jumps; line sizer 255 B | yes | far form (safe, larger) | self-host | **4,096** (beyond: far form, still correct) |

## Defects

| # | Defect | Evidence | Fix |
|---|---|---|---|
| D1 | DOEXIT exited when its condition was **false** (design.md says true) | d40 printed `10`, not `32` | **fixed (step 3):** `_emit_struct_branch_if_true` inverts the skip branch; d40 prints `32` |
| D2 | A compare with `r2` on the left emitted `ceq r2,r1`; only `ceq r1,r2` (and r0 pairs) is encodable | d26 assembly check | **fixed (step 3):** `_emit_inst2` swaps `ceq` register operands into ascending order |
| D3 | `0b` literals reached `lc` unconverted (`lc r2,0b10`) | d32 assembly check | **fixed (step 3):** `_emit_inst2` emits a `0b` second operand in decimal (via `_emit_dec24`, so 0-999 until step 4 widens it) |
| D4 | SET symbols of 6 or more chars silently failed (L2) | d32 golden | **fixed (step 4):** 31-char names; d18, d20, d32, d34 and d35 now emit the blocks their long-named symbols select (d18 and d20 had been emitting nothing) |
| D5 | Default params `&V=5` store the name as `V=5`; `&V` then expands to empty even when an argument is passed | audit B6 | **fixed (step 6):** the name ends at `=`; the default (at most 63 chars, ERROR beyond) is kept in the macro header (see M2) |
| D6 | `\xNN` string escape gave `x`,`N`,`N`; unknown escapes dropped the backslash | audit G4 | **fixed (step 5):** `\xNN`, `\\`, `\"`, `\'` added; unknown escapes and bad hex digits stop with an ERROR |
| D7 | The demos' own fake source lines (`sub r0,r0`, `xor r0,r0`, `shl r0,1`, `sub r0,1`, undefined `_body`) | `check_structured_asm.sh` | **fixed (steps 3-4)** in the structured demos: rewritten as `lc r0,0`, `shl r0,r1`, `add r0,-1`, `nop`; every structured demo now assembles. The non-structured demos d05, d07 and d10 still contain `sub r0,1` (not checked by the assembler test) |
| D8 | Docs were stale: the arena spans 0xC0000-0xC125B (4,700 B), not 0xC055E; the main buffer is 32,767 B, not 4,096 | audit | **fixed (step 4):** `hlasm.s` header and `docs/bootstrap.md` updated |
| D9 | An indented macro call (` PUTC r0`) passed the macro name as the first argument | found writing d41 | **fixed (step 5):** `_get_arg_start` skips the indentation like `_lookup_macro` |
| D10 | IF/DOEXIT/WHEN compares with a constant outside -128..127 emitted an invalid `lc` | found writing d41 | **fixed (step 5):** `_emit_inst2` loads such constants with `la` |
| D11 | cor24-asm rejects label arithmetic in `.word` (`.word mark+3` in d33 passes through hlasm but has never been assembled) | found writing d41 | open: an assembler limitation, not hlasm; d33 only checks hlasm's text |
| D12 | A conditional nested inside a skipped conditional was evaluated on its own, so a true inner IFDEF/IFEQ/IFNE (or an ELSEASM) turned output back on inside the skipped block | found writing d42 | **fixed (step 6):** a conditional pushed inside a skipped region gets state 2 (skipped by its parent), which ELSEASM does not flip |

## Language gaps

| # | Gap | Today | Needed by | Plan |
|---|---|---|---|---|
| M1 | Symbol values in operands (EQU) | SET drove conditionals only | ports (named constants, MMIO addresses), plsw | **done (step 5):** in instruction, `.byte` and `.word` operands (source and macro expansions) and IF/DOEXIT/WHEN compares, an operand whose identifiers are all SET/EQU symbols and that has something to compute is emitted as its decimal value; in `d(reg)` only `d` is rewritten. Registers, labels and plain literals pass through unchanged. Syntax stays HLASM-style `name EQU expr` (and `SET name,expr`) |
| M2 | Default and keyword params (B6) | broken (D5) | library macros with optional args | **done (step 6):** `&V=5` in the header; at the call `V=7` sets parameter V by name, in any order with positional arguments; an omitted or empty argument takes the default. Arguments may contain commas and blanks inside quotes or parentheses (`','`, `' '`, `(a,b)`) |
| M3 | Directives inside macro bodies (B5) | bodies are raw text | library macros that vary with argument count or target | **done (step 6):** a call pushes an expansion frame (depth 8) and `_read_line` feeds the substituted body lines back through the line processor, so bodies may hold macro calls (L10), SET/EQU, conditional assembly, structured IF/DO/SELECT and data directives. `&SYSNARG` gives the positional argument count and `&SYSNDX` the expansion number (same as `\@`); IFEQ/IFNE now take an expression as their first operand, so `IFNE &SYSNARG,1` works |
| M4 | Expressions (G2) | `+` and `-` only; `*`, `/`, `<<`, `( )`, `'A'` gave 0 | table offsets, sizes | **done (step 5):** `\| ^ & << >> + - * / %` with C precedence, unary `- ~ +`, `( )`, `'c'` literals; `>>` is arithmetic, `/` and `%` truncate toward zero, division by zero is an ERROR |
| M5 | Compound conditions (G1) | extra terms silently ignored | plsw | `IF cc_eq,r0,1,AND,cc_ne,r1,2` lowered as short-circuit branches; error on malformed input |
| M6 | DSECT / FIELD (G3) | passes through raw | plsw records, services control blocks | `DSECT name` / `FIELD name,size` / `DEND` defining offset symbols via M1 |
| M7 | Diagnostics (G6) | no file or line context; overflows silent | everyone | **done (step 7):** every `_fatal` prints `ERROR: <member>:<line>: <message>`. Each source keeps its own line number (an include returns to the caller's count); a macro expansion reports the call line; the main source is named after its file (by the source-set runner) or `main`. HLDIAG warnings keep their existing `src N line M` format, and since `_fatal` halts, an HLDIAG count adds nothing |

## Cost (G7)

Measured over both relaxation passes:

| Input | Instructions | Per line |
|---|---|---|
| d31 (129 lines, 5,284 B) | 1.87M | ~14,500 |
| 1000 x ` add r0,1` | 8.30M | ~8,200 |
| 1000 x 75-char comments | 9.83M | ~9,700 |
| 1000 calls of a 2-line macro | 10.15M | ~10,000 per call |
| 300 x IF / nop / ENDIF | 13.17M | ~14,600 |

Fixed overhead is about 0.1M. Estimate 10-15K instructions per source line:
about 300-450M for a 30K-line build, and about 150M for self-hosting
hlasm's 12K lines. That is acceptable at `--speed 0` with plsw-style budgets
(`-n 2000000000`).

Step 4 added about 10K instructions of fixed cost per run (clearing the
work area and the larger relax flag tables at pass start): d01 went from
116,864 to 126,601 and d31 from 1,867,549 to 1,886,538.

Step 5 added operand evaluation on every instruction line, about 8-20%:
d01 126,601 to 136,366, d31 1,886,538 to 2,106,813. A fast path for plain
register and literal operands is the obvious first optimization.

Step 6 sends expanded macro lines through the whole line processor instead
of printing them directly, so macro-heavy sources cost more; plain lines are
unchanged: d01 136,366 to 136,398, d15 176,001 to 191,561, d31 2,106,813 to
2,299,745, d16 392,620 to 447,994 (its test budget was raised to 1M).


Cheap wins, scheduled after correctness:
- skip the sizer's work for comment-only lines in pass 1;
- hash the symbol and macro lookups once the tables reach hundreds of
  entries (a linear scan at 512 entries would otherwise dominate);
- avoid re-reading the include table per line.

## Memory map (implemented in step 4)

The new tables use the unused low SRAM. Source buffers and the config block
stay where they were, so the sourceset tools are unaffected. The same map
is in the "Runtime memory map" comment in `hlasm.s`.

| Range | Use |
|---|---|
| 0x000000-~0x005100 | hlasm image; `_main` stops with an ERROR if it would reach 0x010000 |
| 0x010000-0x014FFF | symbol table: 512 x 40 B (name + NUL at +0, value at +32) |
| 0x018000-0x01A6FF | macro table: 256 x 39 B (name + NUL, body start +33, body end +36) |
| 0x020000-0x02FFFF | macro body pool: 64 KB |
| 0x030000-0x0311DF | work area, cleared at each pass start: input line, token and name buffers, cc/lhs/rhs and WHEN buffers (260 B each), 1 KB expansion buffer, cond/IF/DO/SELECT stacks (32 each), 16 x 32 B parameter names |
| 0x031200-0x0331FF | SELECT selector strings: 32 x 256 B |
| 0x033200-0x03350F | name save buffers for `_symbol_enabled`, `_handle_equ`, `_set_symbol` |
| 0x034000-0x037FFF | XREF symbol names: 512 x 32 B |
| 0x038000-0x0387FF | HLDIAG undefined-symbol names: 64 x 32 B |
| 0x038800-0x038AFF | XREF macro expansion counters: 256 x 3 B (cleared at each pass start) |
| 0x039000-0x0391FF | macro expansion frames: 8 x 64 B (body pointer and end, `\@` number, argument count, 16 argument pointers); depth at 790719 in the arena (step 6) |
| 0x039200-0x03A1FF | argument strings of each frame: 8 x 512 B (step 6) |
| 0x03A200-0x03A5FF | parameter defaults while a MACRO header is parsed: 16 x 64 B (step 6) |
| 0x03A600-0x03A78B | source descriptors: 33 x 12 B (base, length, position, line number) (step 7) |
| 0x07F000-0x07F2D8 | source config block, new layout (step 7): member count, main base/length overrides, main name, then 32 x 22 B member records (base, length, 16-byte name) |
| 0x080000-0x0BFFFF | source buffers |
| 0x0C0000-0x0C125B | arena: counters, source descriptors, source-return stack (cleared at each pass start) |
| 0x0D0000 | relax snapshot |
| 0x0E0000-0x0ECFFF | relax state and tables, 4,096 entries |

Rule for the snapshot: everything that `_relax_snapshot` must restore is
either in the two image regions or is re-initialised at pass start. The
moved tables are only read below their counts, and the counts live in the
arena, which is cleared at pass start, so the tables themselves need no
snapshot. About 1.8 KB of dead legacy tables in the image (`_symbol_table`,
`_macro_table`, `_macro_buf`, `_expand_buf`, `_cond_stack`, `_src_desc*`,
`_parse_name_buf` and the 128-byte `_line_buf`) were removed.

## Overflow policy (implemented in step 4)

Every table has one guard that calls the shared routine `_fatal(msg)`. It
prints `ERROR: <message>` on the UART (also during the sizing pass, by
switching to the emitting path) and halts with `bra` to self, which
cor24-emu detects. Nothing hangs, truncates, or drops data silently. Since
step 7 the message reads `ERROR: <member>:<line>: <message>` (M7).

## System services plan (storage, printing, buffer I/O)

Ported programs and plsw need the same handful of services. They are
provided as an hlasm macro library with **one interface and per-target
implementation members**. The target is chosen by which member the program
COPYs or INCLUDEs.

### Interface (macros)

| Macro | Purpose |
|---|---|
| `GETMAIN reg,size` / `FREEMAIN reg,size` | storage from an arena (bump allocator with a free list) |
| `PUTC reg`, `PUTS label`, `PUTDEC reg`, `PUTHEX reg`, `PUTNL` | console output |
| `GETC reg`, `GETLINE buf,len` | console input |
| `WTO 'text'` | write a literal message (string emitted out of line with `\@`) |
| `DCB name,...` | control block for a named buffer ("file"): base, length, position, flags (laid out with M6 DSECT) |
| `OPEN dcb` / `CLOSE dcb` / `GET dcb,reg` / `PUT dcb,reg` / `READ dcb,buf,len` / `WRITE dcb,buf,len` | buffer I/O |
| `EXIT code` | terminate |

### Targets

- **`svc_bare.hlasm`** (bare metal, cor24-emu or the FPGA):
  - Console uses UART MMIO directly: data at 0xFF0100, status at 0xFF0101,
    polling the TX-busy bit.
  - GETMAIN draws on a static arena.
  - Input files are preloaded memory buffers (`--load-binary f@addr`, as
    hlasm's own sources are) or arrive over the UART framing protocol
    below.
  - `EXIT` spins (`bra` to self), which is the hardware halt idiom.
- **`svc_swtos.hlasm`** (sw-tos):
  - Calls go through the generated glue stubs only.
  - Console uses IPC to the TTY server (MSG_TTY_WRITE=1,
    MSG_TTY_READ_LINE=2, via SYS_SENDREC=5).
  - `EXIT` uses SYS_EXIT=2.
  - GETMAIN uses the sw-tos allocator.
  - Until sw-tos has a filesystem, a "file" is a named buffer. The DCB
    interface is unchanged when the filesystem module arrives.

Choosing the target by COPY needs nothing new from hlasm beyond the lifts
above (L8, L10, M1, M2). M3 lets one member hold both targets behind
`IFDEF`. Separate compilation through sw-tos's `link24` is a later option.
hlasm's output is plain `.s`, which link24 already consumes, so the services
could become a prebuilt module rather than COPYed source.

### UART framing protocol (batch I/O over one serial line)

To run in the emulator or on hardware, a compiler-like program (plsw,
hlasm itself later) needs several named inputs and one structured output
over a single UART. The protocol already used by
`sw-cor24-plsw/src/main.c` and `sw-tos/scripts/catalog-spawn-link.sh` is
adopted unchanged, so an HLASM-built plsw is a drop-in replacement.

Input (host to program):

```
c\n                                    mode line: c = compile, r = REPL (case-insensitive)
FILE:<name>\n<content>\x1E             zero or more named members (RS terminates each)
SOURCE:\n<content>\x04                 main source; \x04 (EOT) ends input, \x03 aborts
```

- Header lines (`FILE:...`, `SOURCE:`) are at most 80 characters.
- `\x04` or `\x03` inside a FILE member is an error.
- Legacy form: raw source followed by `\x04`, with no `SOURCE:` prefix.

Output (program to host):

```
<banner and prompt>
  registered: <name>                   one line per FILE member
--- generated assembly ---
<.s text>
--- end assembly ---
```

On failure the output is `ERROR: <message>` lines and
`--- compilation failed ---`. The host script greps for the error and end
markers and extracts the `.s` between the markers.

Library support:
- `UFRAME_READ` reads the mode line and the members into GETMAIN'd
  buffers and registers each FILE as a DCB, so `OPEN name` works on it.
- `UFRAME_BEGIN` / `UFRAME_END` / `UFRAME_FAIL` emit the markers.
- The same framing is the planned host interface for hlasm itself. It
  would replace the host-side `.bin`, config-block, and `--load-binary`
  path for users who only have a serial line (see L19).

## Schedule

Ordered so that the tiny-C ports (steps after these) have correct
lowering, real tables, named constants, and layered macros. Items that only
plsw or self-hosting need come later.

In this saga (tinyc-macro-ports), inserted after step 2:

1. **fix-lowering-defects** (saga step 3, done): D1 DOEXIT polarity, D2 `ceq` operand order,
   D3 `0b` literals, D7 the demos' fake instructions.
   `check_structured_asm.sh` must report every structured demo `ok`.
2. **capacity-tables-and-guards** (saga step 4, done):
   - L1, L2, L4, L6, L8, L9, L11-L17, L22-L24, D4, D8.
   - Move the tables to the new memory map, add the `_fatal` overflow
     policy, add limit + 1 tests, and remove the dead legacy tables.
3. **equ-and-expressions** (saga step 5, done): M1 (EQU and operand substitution), M4
   (expression evaluator), D6 (`\xNN`).
4. **macro-layering** (saga step 6, done): L10 and M3 (re-feed expansions through the line
   processor: nested calls and directives in bodies), M2 and D5
   (default and keyword params), D12 (nested conditionals in skipped blocks).
5. **include-capacity-and-diagnostics** (saga step 7, done): L19-L21 (new config layout, 32
   members, 15-char names, nesting 16) and M7 (member:line in errors).

Then the existing steps continue: e2e harness, survey, the macro library
(which implements the services interface's bare-metal target, console and
storage first), the ports, and the showcase.

**Future saga (plsw-readiness):**
- M5 compound conditions and M6 DSECT/FIELD;
- the sw-tos services target and buffer I/O;
- UART framing library (`UFRAME_*`), and hlasm accepting framed input;
- G7 cost wins.

**Future saga (self-host):** `docs/bootstrap-hlasm.md`. Its prerequisites
are the five steps above.
