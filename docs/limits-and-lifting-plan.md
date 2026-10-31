# hlasm Limits and Lifting Plan

Status: audit complete (2026-10-31, tinyc-macro-ports saga step 2). Lifts are
scheduled as saga steps (see "Schedule").

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

The audit's scratch tests are reproducible. Each is a `.hlasm` file run
through hlasm at a chosen size; they become regression tests when each lift
lands.

## Limits table

Key to the Check column:
- "none": no bound check; overflow corrupts or hangs.
- "silent": checked, but the excess is dropped without a message.

| # | Limit | Today | Check | Overflow | Needed by | Lift to |
|---|---|---|---|---|---|---|
| L1 | Symbol entries | 16 x 9 B | none | 17-19 corrupt the cond stack; 20 or more hang | ports, plsw B1, self-host | 512 |
| L2 | Symbol name length | 5 chars | none | lookup fails silently | everyone | 31 chars |
| L3 | Symbol value | 24-bit, wraps | - | wraps | - | keep (24-bit machine) |
| L4 | Macros | 32 x 39 B | none | 33 or more hang | macro library, plsw B1 | 256 |
| L5 | Macro name | 31 chars | silent | rest dropped | - | keep; give an error |
| L6 | Named params | 8, names of at most 8 chars | silent | dropped or mangled | library macros | 16 params, 31-char names |
| L7 | Positional params | `&1`-`&9` | - | missing argument gives empty | - | keep |
| L8 | Macro body pool | 1,023 B **total** | none | truncated; empty at about 1,160 B | macro library (fatal today) | 64 KB |
| L9 | Expansion buffer | 129 B | none | 132 B corrupts `\@`; 140 B or more swallows the rest of the source | long macro lines | 256 B, checked |
| L10 | Nested macro calls | not supported | - | inner call emitted raw | library layering (PUTS calls PUTC), plsw B5 | expansion stack, depth 8 |
| L11 | `\@` counter | 0001-9999 | none | `L:000` (invalid label) | self-host | 6 digits |
| L12 | Cond-asm stack | 8 x 3 B | none | overwrites the src-return stack; at 9 levels inside an INCLUDE the rest of the parent file is lost | plsw B3 | 32, checked |
| L13 | IF / DO / SELECT depth | 8 each | silent | opener dropped, body emitted unconditionally | plsw B3 | 32, error |
| L14 | cc / lhs / rhs operand buffers | 16 B each | none | operands spill into each other; DO depth corrupted | long names | 32 B, checked |
| L15 | Selector / WHEN buffers | 12 B (x8) | none | overflow into the EOF flag and param count | - | 32 B, checked |
| L16 | Structured label id | 999 | none | `_hlif_:00_false`; cor24-asm rejects it | ports, self-host (B4) | 6 digits; relax tables 4,096 |
| L17 | Input line | nominal 128 B; arena space 165 B | **none** | 166 B garbage; 175 B or more hang | plsw G5 | 256 B, error past the limit |
| L18 | Main buffer | 32,767 B default (docs say 4,096) | stops at length or NUL | truncated mid-line | self-host | sourceset sets the length; document it |
| L19 | Extra buffers / include slots | 3 (config block layout) | host-side only | - | macro library members, self-host | 32 records; new config layout |
| L20 | Include name | 8 chars | host-side only | - | readable member names | 15 chars |
| L21 | Include nesting | 8 | silent | INCLUDE ignored | - | 16, error |
| L22 | HLXREF symbols / HLDIAG names | 16 x 16 B | silent | extras ignored | larger programs | follow L1 |
| L23 | XREF expand counts | 16 B (but 32 macros) | none | macros 17-32 corrupt `_xref_symbol_count`, even with HLXREF off | - | follow L4 |
| L24 | Relax tables | 1,024 ids or jumps; line sizer 255 B | yes | far form (safe, larger) | self-host | 4,096 |

## Defects (wrong output today)

| # | Defect | Evidence | Fix |
|---|---|---|---|
| D1 | DOEXIT exits when its condition is **false** (design.md says true) | d40 prints `10`, not `32` | invert the lowering; update the d12/d29 goldens |
| D2 | A compare with `r2` on the left emits `ceq r2,r1`; only `ceq r1,r2` (and r0 pairs) is encodable | d26 assembly check | swap the operands for symmetric conditions; for `cls`/`clu` all orders are encodable |
| D3 | `0b` literals reach `lc` unconverted (`lc r2,0b10`) | d32 assembly check | convert to decimal like `0x`/`h` |
| D4 | SET symbols of 6 or more chars silently fail (L2) | d32 golden | fixed by the L2 lift; rebase the d32 golden |
| D5 | Default params `&V=5` store the name as `V=5`; `&V` then expands to empty even when an argument is passed | audit B6 | parse `=default` (see M2) |
| D6 | `\xNN` string escape gives `x`,`N`,`N`; unknown escapes drop the backslash | audit G4 | add `\xNN`; error on unknown escapes |
| D7 | The demos' own fake source lines (`sub r0,r0`, `xor r0,r0`, `shl r0,1`, undefined `_body`) | `check_structured_asm.sh` | rewrite with encodable instructions (e.g. `lc r0,0`) |
| D8 | Docs are stale: the arena spans 0xC0000-0xC125B (4,700 B), not 0xC055E; the main buffer is 32,767 B, not 4,096 | audit | update `docs/bootstrap.md` and the `hlasm.s` header |

## Language gaps

| # | Gap | Today | Needed by | Plan |
|---|---|---|---|---|
| M1 | Symbol values in operands (EQU) | SET drives conditionals only | ports (named constants, MMIO addresses), plsw | `EQU name,expr` and SET values substituted for whole-word identifiers in operand fields, emitted as decimal literals |
| M2 | Default and keyword params (B6) | broken (D5) | library macros with optional args | `&V=5` header syntax; keyword args `V=7` at the call |
| M3 | Directives inside macro bodies (B5) | bodies are raw text | library macros that vary with argument count or target | re-feed expanded lines through the line processor (which also gives L10) |
| M4 | Expressions (G2) | `+` and `-` only; `*`, `/`, `<<`, `( )`, `'A'` give 0 | table offsets, sizes | precedence-climbing evaluator: `* / % << >> & \| ( )` and character literals |
| M5 | Compound conditions (G1) | extra terms silently ignored | plsw | `IF cc_eq,r0,1,AND,cc_ne,r1,2` lowered as short-circuit branches; error on malformed input |
| M6 | DSECT / FIELD (G3) | passes through raw | plsw records, services control blocks | `DSECT name` / `FIELD name,size` / `DEND` defining offset symbols via M1 |
| M7 | Diagnostics (G6) | no file or line context; overflows silent | everyone | `ERROR: <member>:<line>: <message>` on the UART, and a non-zero `HLDIAG` count |

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

Cheap wins, scheduled after correctness:
- skip the sizer's work for comment-only lines in pass 1;
- hash the symbol and macro lookups once the tables reach hundreds of
  entries (a linear scan at 512 entries would otherwise dominate);
- avoid re-reading the include table per line.

## Memory map after the lifts

The new tables go into the unused low SRAM. Source buffers and the config
block stay where they are, so the sourceset tools are unaffected.

| Range | Use |
|---|---|
| 0x000000-~0x006000 | hlasm image (grows with the lifts) |
| 0x010000-0x017FFF | symbol table: 512 x 40 B (31-char name + NUL, value, flags) |
| 0x018000-0x01FFFF | macro table: 256 x 48 B, plus parameter descriptors |
| 0x020000-0x02FFFF | macro body pool: 64 KB |
| 0x030000-0x0303FF | expansion stack: 8 x 256 B line buffers + state |
| 0x030400-0x0307FF | cond stack (32), IF/DO/SELECT stacks (32 each), operand buffers |
| 0x07F000 | source config block (new layout: up to 32 records, 15-char names) |
| 0x080000-0x0BFFFF | source buffers |
| 0x0C0000-0x0C125B | existing arena (remaining small state, line buffer moved to 256 B) |
| 0x0D0000 | relax snapshot (now includes the moved tables' counters only) |
| 0x0E0000- | relax tables, 4,096 entries (about 49 KB) |

Rule for the snapshot: everything that `_relax_snapshot` must restore is
either in the two image regions or is re-initialised at pass start. New
tables are re-initialised (counts zeroed) at pass start, not snapshotted.
The 1.6 KB of dead legacy tables in the image (`_symbol_table`,
`_macro_table`, `_macro_buf`, and similar) is removed at the same time.

## Overflow policy

Every table gets one guard, implemented as a shared routine:
`_fatal(msg)` prints `ERROR: <member>:<line>: <table> overflow` and halts
(`bra` to self). Nothing hangs, truncates, or drops data silently. A reg-rs
test per table hits its limit + 1 and checks for the message.

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

1. **fix-lowering-defects:** D1 DOEXIT polarity, D2 `ceq` operand order,
   D3 `0b` literals, D7 the demos' fake instructions.
   `check_structured_asm.sh` must report every structured demo `ok`.
2. **capacity-tables-and-guards:**
   - L1, L2, L4, L6, L8, L9, L11-L17, L22-L24, D4, D8.
   - Move the tables to the new memory map, add the `_fatal` overflow
     policy, add limit + 1 tests, and remove the dead legacy tables.
3. **equ-and-expressions:** M1 (EQU and operand substitution), M4
   (expression evaluator), D6 (`\xNN`).
4. **macro-layering:** L10 and M3 (re-feed expansions through the line
   processor: nested calls and directives in bodies), M2 and D5
   (default and keyword params).
5. **include-capacity-and-diagnostics:** L19-L21 (new config layout, 32
   members, 15-char names) and M7 (member:line in errors).

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
