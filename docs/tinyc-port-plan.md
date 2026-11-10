# Porting the tiny-C demos to hlasm

Status: done (2026-11-10). Written as the plan in saga `tinyc-macro-ports`
step 9; all 42 ports landed in steps 12-17. Results are in
[c-demos-in-hlasm.md](c-demos-in-hlasm.md).

This plan covers porting the example programs in
`../sw-cor24-x-tinyc/demos`, written in C and compiled by tc24r, to hlasm
source that uses a shared macro library. It is the porting method that
`sw-cor24-plsw/docs/migrate-from-c-to-hlasm.md` reuses for the PL/SW
compiler, so the calling convention, library layout and gap list here
are meant to carry over unchanged.

The user-facing write-up of the finished ports is
[c-demos-in-hlasm.md](c-demos-in-hlasm.md).

## What was surveyed

`../sw-cor24-x-tinyc/demos` holds 68 C programs:

- `demo.c` and `demo2.c` through `demo64.c`;
- `hello.c`, `uart_tx.c`, `led.c` and `button.c`.

60 of them have tc24r output checked in as `.s`, and 64 have a
`run-demoN.sh` script. Almost every numbered demo is a self-test with the
same shape: `main` runs a set of checks, prints `DnOK` on the UART if they
all pass, and returns a known value, usually 42 (51-59 and 62-63 return
their own number). The run script checks that the CPU halted, that r0
holds that value, and that the UART log contains the marker.

Each demo was written to exercise one tc24r front-end feature, and that
shapes the port: many of them test C syntax that has no counterpart in
assembly (typedef, line continuation, tentative definitions). Those are
skipped; see [Demos to skip](#demos-to-skip).

## 1. Recurring idioms

Counts are from the 60 checked-in `.s` files.

### UART output

Every demo that prints defines its own `putc` and `puts`, or gets
`_putc_uart`/`puts` from `<stdio.h>`. `__putc_uart` is the most called
routine in the corpus (522 call sites):

```c
void putc(int c) { while (*(char *)0xFF0101 & 0x80) {} *(char *)0xFF0100 = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }
```

tc24r turns the 2-line `putc` into a 25-instruction routine, with a full
frame and a push/pop around each constant load. As a macro it is 7
instructions inline (see `PUTC` below).

### Decimal and hex printing

`printf` (`<stdio.h>`) is split by tc24r into `__tc24r_printf0..3`,
which call `_fmt_one`, which calls `_print_int`, `_print_hex` and
`_print_str`. 22 demos include `<stdio.h>`, but most use only `puts`;
demo39 and the Lisp demos use `%d`.

### LED and button

`LED_REG` 0xFF0000 is active-low: write 0 to turn LED D2 on. The button
is S2, bit 0 of the same address, which reads 0 while pressed. They are
used by `led.c`, `button.c`, demo2, demo8 and demo10.

### Function frame and calls (tc24r calling convention)

The hlasm library adopts this convention exactly, so HLASM routines and
tc24r routines can call each other. This is needed for the plsw hybrid
build.

```
caller:  push argN ... push arg1     (arguments right to left, one word each)
         la   r0,_fn
         jal  r1,(r0)
         add  sp,3*N                 (caller pops its arguments)
callee:  push fp / push r2 / push r1 / mov fp,sp     (prologue)
         sub  sp,LOCALS              (locals below fp, if any)
         arg1 at 9(fp), arg2 at 12(fp), ...; locals at -3(fp), -6(fp), ...
         result in r0
         mov sp,fp / pop r1 / pop r2 / pop fp / jmp (r1)  (epilogue)
```

- r0 and r1 are scratch. r2 is preserved by the prologue and epilogue,
  so a callee may use it freely.
- Labels are the C name with a leading `_`. `_start` calls `_main` and
  then spins on `_halt: bra _halt`.
- Frames are adjusted with `add sp,±n` up to 127 and `sub sp,n` beyond
  that: demo50's 256-byte local buffer uses `sub sp,259`.
  `lw`/`sw` offsets are 8-bit, so locals beyond -128(fp) need an address
  computed with `mov`/`add`. That was tc24r's BUG-013.

### Compare and branch

tc24r compares with `ceq`, `cls` and `clu`, branches with `brt`/`brf`, and
materialises every comparison result as 0/1 before testing it. Those are
the hlasm structured conditions `cc_eq`, `cc_ne`, `cc_lt` and `cc_lu`.
C also uses `<=`, `>` and `>=`, signed and unsigned (demo46 is all of
them). hlasm has `cc_le`, `cc_gt`, `cc_ge` and `cc_leu`, `cc_gtu`,
`cc_geu` for these since step 10 (gap M8).

### Loops

C `while`, `do`/`while` and `for` are all `DO ... DOEXIT ... ENDDO`.
`continue` is `ITERATE` and `break` is `DOEXIT` with no operands.
`for (i = a; i < b; i++)` has an initialiser before `DO` and an increment
before `ENDDO`. `continue` in a `for` loop must still run the increment,
so the increment goes at the top of the next pass or `ITERATE` targets a
label before it. demo13 shows both cases.

### Self-test checks

Nearly every demo is a list of `if (x != expected) { ok = 0; }` lines, or
calls to a `check(cond, id)` helper (demo46). This is the most repeated
source pattern in the corpus, and a `CHECK` macro makes each line one
statement (see the API below).

### Multiply, divide, modulo

COR24 has `mul` but no divide. tc24r emits `__tc24r_div` and
`__tc24r_mod` routines (25 and 36 call sites; demo4, demo13 and the
`%`-heavy demos). The library provides them as routines, with `DIV`/`MOD`
macros that call them.

### Arrays and pointers

- Element addressing is `base + i*3` for `int` and `base + i` for `char`,
  computed with `shl`/`add` or `mul`.
- Pointer subtraction divides by 3 (demo7).
- Global arrays are `.word`/`.byte` lists or `.space`.
- Multi-dimensional arrays are row-major (demo34).

### Structs and unions

Member access is `base + offset`. Offsets come from the declaration
order: one word per `int` and pointer, one byte per `char`, and arrays
of members are counted in full (demo35). Union members all have offset
0. In hlasm the offsets are `EQU` symbols computed with expressions,
until M6 DSECT/FIELD exists.

### Strings and data

- String literals become `_Sn: .byte ...,0` in `.data`.
- Globals with initialisers become `.word`/`.byte` lists (demo58).
- Adjacent literals are joined (demo63).
- hlasm already turns `.ascii "text\n"` into a `.byte` list with escapes
  resolved. cor24-asm has no separate data section (`.data`/`.text` are
  accepted but ignored), so string data must be placed where execution
  does not reach; see the "as built" note in section 2.

### Heap

`<stdlib.h>` `malloc` is a bump allocator over a static arena, and `free`
does nothing. demo40, demo43, demo44 and demo45 use it. This maps onto
`GETMAIN`/`FREEMAIN` in the services interface.

### Function pointers

These are `la r0,_fn` stored in a word and called as `jal r1,(r0)`
(demo51-54). They need no macro beyond `CALL` accepting a register or
memory operand as the target.

### Interrupts

demo9 installs an interrupt handler: `la r0,_isr` / `mov iv,r0`, enable
at 0xFF0010, and the handler returns with `jmp (ir)`. hlasm passes these
lines through unchanged, so no macro is needed.

## 2. Macro library API and layout

**As built (step 11).** The library is in `lib/`, and the authoritative
macro reference is
[c-demos-in-hlasm.md](c-demos-in-hlasm.md#the-macro-library). It differs
from the proposal below in these ways:

- The code members are `svc_bare_code` and `rt_code`. `rt.hlasm` holds only
  macros: `DIV`, `MOD`, and `RTCALL name,args` for the string routines.
- cor24-asm has no data section, so nothing is emitted "out of line":
  - `WTO` calls `_svc_wto`, which prints the text stored right after the
    call.
  - The data macros place their data where they are called (after a `RET`).
  - `CHECKINIT` jumps over its flag word.
- `START` and `EXIT` are in `svc_bare`, not `frame`.
- `CALL` pops only the arguments it actually pushed. Empty arguments passed
  on by wrapper macros are skipped.
- `PUTHEX` prints without leading zeros, like tc24r's `%x`.

### COPY member layout

The library lives under `lib/`. A program pulls members in with `COPY`
through its `.sourceset`, and `demos/tinyc/lib.sourceset` lists them
once for all ports:

| Member | Contents | Kind |
|---|---|---|
| `lib/cor24.hlasm` | `EQU`s for the board: `UART_DATA`, `UART_STATUS`, `UART_TXBUSY`, `LED_REG`, `INT_ENABLE`, `LED_ON`, `LED_OFF` | symbols only |
| `lib/frame.hlasm` | `PROLOG`, `RET`, `RETURN`, `CALL`, `ARG`, `LOCAL`, `START` | macros only |
| `lib/svc_bare.hlasm` | services interface, bare-metal target: `PUTC`, `PUTS`, `PUTDEC`, `PUTHEX`, `PUTNL`, `WTO`, `GETC`, `GETLINE`, `GETMAIN`, `FREEMAIN`, `EXIT` | macros |
| `lib/svc_bare_rt.hlasm` | the routines those macros call: `_svc_puts`, `_svc_putdec`, `_svc_puthex`, `_svc_getc`, `_svc_getline`, `_svc_getmain` and the arena | code |
| `lib/board.hlasm` | `LEDON`, `LEDOFF`, `BUTTON reg` | macros |
| `lib/rt.hlasm` | runtime routines: `_div`, `_mod`, `_strlen`, `_strcmp`, `_strcpy`, `_memcpy`, `_memset`, `_atoi`, plus `DIV`/`MOD` macros | code and macros |
| `lib/data.hlasm` | `STR label,"text"` (a NUL-terminated string in `.data`), `WORDS label,v1,...`, `BYTES label,v1,...`, `SPACE label,n` | macros |
| `lib/check.hlasm` | `CHECKINIT`, `CHECK cond,a,b`, `CHECKEND 'marker',rc`: the self-test pattern | macros |

Rules:

- **Macros-only members** (`cor24`, `frame`, `svc_bare`, `board`, `data`,
  `check`) can be COPYed at the top of any program, because they emit no
  code until they are called.
- **Code members** (`svc_bare_rt`, `rt`) are COPYed at the end, after the
  program's own routines. Each routine sits inside `IFDEF NEED_<name>`.
  The macros that call a routine `SET NEED_<name>,1`, so only routines
  that were used are emitted. tc24r does the same job with a dead-code
  pass, which demo64 checks. Conditional assembly does it here, which is
  one of the macro features the showcase demonstrates.
- **Each member has an include guard** (`IFNDEF LIB_<member>` /
  `SET LIB_<member>,1`), so a member listed twice is harmless.
- **Library labels** are `_svc_*`, `_rt_*` or the C library name (`_strlen`)
  where a tc24r program would call it. Macro-local labels use `\@`.
- **Choosing the target.** The services interface is the one in
  [limits-and-lifting-plan.md](limits-and-lifting-plan.md#system-services-plan-storage-printing-buffer-io).
  A later `lib/svc_swtos.hlasm` provides the same macros over sw-tos IPC.
  A program chooses its target by which member it COPYs; nothing else
  changes.

### Macro reference (proposed)

Register effects follow the calling convention: macros may clobber r0
and r1 and preserve r2 unless stated.

| Macro | Expands to | Effect |
|---|---|---|
| `PROLOG [locals]` | `push fp`/`push r2`/`push r1`/`mov fp,sp`; then `add sp,-n` (n ≤ 127) or `sub sp,n` | locals in bytes, default 0 |
| `RET` | `mov sp,fp`/`pop r1`/`pop r2`/`pop fp`/`jmp (r1)` | result already in r0 |
| `RETURN value` | load value into r0, then `RET` | |
| `ARG reg,n` | `lw reg,9+3*(n-1)(fp)` | nth argument (1-based) |
| `LOCAL name,bytes` | `name EQU -offset` from a running `SET` counter; `PROLOG` uses the total | named locals as fp offsets |
| `CALL fn[,a1,...,a8]` | push the arguments right to left (a constant or label with `la r0,`, a register with `push`), `la r0,fn`/`jal r1,(r0)`, then `add sp,3*N` | result in r0 |
| `START [main]` | `_start: la r0,_main`/`jal r1,(r0)`, an optional r0 report, `_halt: bra _halt` | program entry |
| `PUTC [reg]` | wait for TX not busy, `sb reg,0(UART)` (inline, 7 instructions including `push`/`pop r2`) | default r0 |
| `PUTS label\|reg` | `CALL _svc_puts,arg` | NUL-terminated string |
| `PUTDEC reg`, `PUTHEX reg` | `CALL _svc_putdec`/`_svc_puthex` | signed decimal; 6 hex digits |
| `PUTNL` | `PUTC` of 10 | |
| `WTO "text"` | the string out of line in `.data` (`S\@`), then `PUTS S\@` | escapes resolved by hlasm |
| `GETC reg` | `CALL _svc_getc` | -1 at EOF (0x04) |
| `GETLINE buf,len` | `CALL _svc_getline` | length in r0 |
| `GETMAIN reg,size` / `FREEMAIN reg,size` | bump allocation from the arena / no-op (as tc24r's `free`) | |
| `EXIT [code]` | load code into r0, `bra _halt` | |
| `LEDON` / `LEDOFF` / `BUTTON reg` | `sb` 0/1 to `LED_REG`; `lb reg`, mask bit 0 | |
| `DIV a,b` / `MOD a,b` | `CALL _div,a,b` / `CALL _mod,a,b` | signed, truncating like C |
| `STR label,"text"` | `.data`/`label: .ascii "text"`/`.byte 0`/`.text` | |
| `CHECKINIT` / `CHECK cond,a,b` / `CHECKEND 'DnOK',rc` | clear an ok flag when `cond a,b` is false; at the end print the marker and return rc if all checks passed, else return 0 | the demo self-test |

**Result checking.** The tc24r run scripts check r0 through
`cor24-emu --dump`, but the hlasm e2e harness checks UART output only.
`START` therefore prints `r0=<n>` after `_main` returns when `SET
SHOWRC,1` is in effect, and every port turns it on. A port's expected
output is the C demo's marker followed by `r0=42` (or the demo's own
value), which checks the same two things the tc24r run script does.

## 3. Which demos to port

The order runs from simple to complex. Each group is one saga step, and
every port gets an `hlasm_e2e_tinyc_<demo>` reg-rs test.

### Group A: I/O (step `port-io-demos`)

| Demo | Shows | Library |
|---|---|---|
| `uart_tx` | raw UART writes | `PUTC` |
| `hello` | string iteration | `PUTS`, `STR`, `START` |
| `led` | LED on | `LEDON` |
| `button` | read S2 and show it on the LED | `BUTTON`, `LEDON`/`LEDOFF`, run with `--switch on` |
| `demo2` | char, pointers, MMIO, prints `OK` | `cor24` `EQU`s, `CHECK` |
| `demo3` | hex literals, pointer walk over a string | `STR`, `PUTS` |
| `demo8` | `#define` constants | `EQU` |
| `demo10` | `#include` and a system header | `COPY` of a demo-local member |
| `demo64` | no-std: copy "hello" to memory and halt | no services at all; shows that unused library routines are not emitted |
| `demo9` | UART RX interrupt | raw `iv`/`ir` lines, run with `-u A` |

### Group B: control flow (step `port-control-flow-demos`)

| Demo | Shows | hlasm construct |
|---|---|---|
| `demo` | functions, recursion (fib), while and for loops, bit operations | `PROLOG`/`CALL`/`RET`, `DO` |
| `demo4` | software divide and modulo | `DIV`/`MOD`, `lib/rt` |
| `demo11` | `&&` and `\|\|` with short-circuit | nested `IF` (until M5) |
| `demo12` | do...while | `DO` with `DOEXIT` at the end |
| `demo13` | break and continue | `DOEXIT`, `ITERATE` |
| `demo14` | `++` and `--` | `add reg,±1`, with no macro needed |
| `demo15` | ternary `?:` | `IF`/`ELSE` |
| `demo21` | compound assignment | plain instructions |
| `demo26` | switch/case | `SELECT`/`WHEN`/`OTHERWISE` |
| `demo46` | signed and unsigned comparisons and shifts | `cc_lt`/`cc_lu`, plus the M8 forms |

### Group C: functions, arrays, pointers, strings (step `port-function-and-data-demos`)

| Demo | Shows |
|---|---|
| `demo5` | arrays: declaration, indexing, decay to pointer |
| `demo6` | global char, pointer and array patterns |
| `demo7` | pointer subtraction |
| `demo16` | character literals (`'a'`, `'\n'`) |
| `demo39` | printf `%d` |
| `demo41` | getc (`-u` input), atoi, strlen/strcmp/strcpy |
| `demo50` | a 256-byte local array with nested calls (frames beyond 127 bytes) |
| `demo51`-`demo54` | function pointers: a variable, a dispatch table, a parameter, a global |
| `demo58` | global data initialisation |
| `demo63` | adjacent string literals |

### Group D: structs, unions and the heap (step `port-struct-and-heap-demos`, inserted)

Group C plus this group came to 22 demos, too many for one step, so the
function/data step was split.

| Demo | Shows |
|---|---|
| `demo23` | enum, as `EQU` |
| `demo25` | struct members, `sizeof` |
| `demo28` | union |
| `demo34` | 2-D arrays |
| `demo35` | arrays inside structs |
| `demo38` | struct initialiser as data |
| `demo40` | malloc/free |
| `demo42` | linked list, chained `->` |
| `demo43` | cons cells: malloc'd structs returned by pointer |

The showcase step may add demo44 (the Lisp printer, 155 lines) as a
larger example if time allows. demo45 (the Lisp evaluator, 300 lines) is
the stretch goal.

### Demos to skip

The skipped demos test C syntax that a programmer writing assembly never
meets, or they repeat a group above:

| Demo | Why skipped |
|---|---|
| demo17 multi-declaration, demo24 typedef, demo30 line continuation, demo31 tentative definitions, demo32 multi-declarator typedef, demo33 comma-separated members, demo36 forward struct tags, demo37 anonymous members, demo22 braceless bodies | C syntax only: they compile to the same code as other demos |
| demo18 and demo29 sizeof, demo55 and demo62 constant expressions in array sizes | covered by `EQU` expressions inside the Group C/D ports |
| demo19 static/extern, demo27 prototypes | no assembly meaning: there is one label namespace, and forward references are free |
| demo20 statement expressions, demo60 compound literals | C extensions with no assembly counterpart |
| demo47, demo48, demo49, demo56, demo57, demo59 | tc24r parser regression tests (BUG-003, -010 to -013) that repeat the struct and array accesses already in Group D |
| demo61 inline asm | the whole program is already assembly |
| demo44, demo45 | large; showcase candidates (see above), not part of the port steps |

That is 42 demos ported and 26 skipped.

## 4. Feature gaps

Cross-checked against
[limits-and-lifting-plan.md](limits-and-lifting-plan.md) (L, D and M
items) and the plsw migration plan (B and G items). Each gap was checked
by running a small program through `scripts/hlasm-e2e.sh`.

### Resolved before this plan

These are already done in hlasm, so the library can rely on them:

- **B5/M3: directives inside macro bodies.** Verified: a `CALL` macro
  that pushes 0-3 arguments using `IFEQ &SYSNARG,n`, and pops them with
  `add sp,(&SYSNARG-1)*3`, ran correctly.
- **B6/M2: default parameters.** `PUTC &R=r0` works.
- **String data from a macro.** The survey believed a `WTO` body could
  switch to `.data` for its text. Building the library showed cor24-asm
  ignores sections and the text ran as code, so `WTO` calls `_svc_wto`,
  which prints the string stored right after the call.
- **Large frames.** `sub sp,n` takes a 24-bit immediate, so `PROLOG`
  needs no conditional for frames beyond 127 bytes.

### New gaps that block the library (inserted as step `condition-forms-and-arg-tests`)

| # | Gap | Found | Why it blocks |
|---|---|---|---|
| M8 | Structured conditions have no `<=`, `>`, `>=` forms (`cc_le`, `cc_gt`, `cc_ge`, and unsigned `cc_leu`, `cc_gtu`, `cc_geu`) | most Group B demos; demo46 uses all of them | Without them every C relational operator becomes swapped operands plus an extra register load, or an inverted `IF ... ELSE`. That is exactly the noise the showcase argues macros remove |
| M9 | Conditional assembly cannot classify a macro argument. There is no text comparison (HLASM `AIF ('&A' EQ 'r2')`), and an undefined name in `IFEQ`/`IFNE` silently evaluates to 0, so `IFEQ &A,r2` is true for any argument that is not a symbol | testing `CALL` | `CALL fn,r2,5,_buf` must `push r2` for a register but `la r0,5`/`push r0` for a constant or label. Without a test it needs separate macros per argument kind, which defeats the point of a single `CALL` |

**Both are done (step 10).** IF/ELSEIF/DOEXIT accept the six condition
forms, and `IFSAME a,b` / `IFDIFF a,b` compare argument text. A non-symbol
name in `IFEQ`/`IFNE` is now an ERROR outside skipped regions. Demo d43
shows a `PUSHARG` macro, the core of the library's `CALL`, that pushes a
register as it is and loads anything else with `la`.

### Known gaps that do not block the ports

| # | Gap | Workaround in the ports | Planned |
|---|---|---|---|
| M5 / G1 | compound conditions (`AND`/`OR`) | nested `IF` (demo11) | plsw-readiness saga |
| M6 / G3 | DSECT/FIELD struct layout | `EQU` offsets with expressions (Group D) | plsw-readiness saga |
| D11 | cor24-asm rejects label arithmetic in `.word` | compute such addresses at run time | assembler issue |
| G7 | assembly time (two passes on the emulator) | none needed at demo size | later cost work |
| — | no `MACRO` definition or `INCLUDE`/`COPY` inside a macro body | not needed by the library | not planned |

Any new gap found during the port steps goes into this table and into
`limits-and-lifting-plan.md`. If it blocks a port, it gets its own saga
step (`agentrail insert`) rather than a workaround.
