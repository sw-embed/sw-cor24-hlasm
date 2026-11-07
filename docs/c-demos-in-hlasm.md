# The tiny-C demos in hlasm

The C compiler tc24r (`../sw-cor24-x-tinyc`) ships about seventy small
demo programs. This document shows those programs rewritten in hlasm,
side by side with the C, using a shared macro library. The point is to
show what macros buy over writing plain COR24 assembly, and how close
hlasm source can come to the C it replaces.

Status: the macro library is done (below); the demos are being ported
in four batches, each added under "Ported demos" as it lands. The detailed survey and reasoning are in
[tinyc-port-plan.md](tinyc-port-plan.md).

## How to run a ported demo

Every port is a source set that COPYs the library members it needs, and
it runs end to end with one command:

```bash
scripts/hlasm-e2e.sh demos/tinyc/hello.sourceset
```

The output is what the program prints on the UART. Like the C demos, each
port prints its `DnOK` marker when its self-checks pass, then `r0=<n>`:
the value `main` returned, which the C demo's run script checks too. Each
port has a regression test named `hlasm_e2e_tinyc_<demo>`.

## The macro library

The library is a set of COPY members under [`lib/`](../lib). A program's
source set names its main file and then includes `lib/lib.sourceset`, which
makes every member available to `COPY`:

```
ROOT .
MAIN hello.hlasm
SOURCESET ../../lib/lib.sourceset
```

Two kinds of member:

- **Macro members** produce no code until a macro is called, so they are
  COPYed at the top of the program.
- **Code members** (`svc_bare_code`, `rt_code`) hold the routines behind the
  macros. They are COPYed at the end, after the program's own routines.
  Each routine sits inside `IFDEF NEED_<name>`, and the macro that calls it
  sets that flag, so a program carries only the routines it uses.

A complete program:

```
COPY cor24
COPY frame
COPY svc_bare
SET SHOWRC,1           ; print "r0=<n>" at exit
 START                 ; _start: call _main, then halt
_main:
 PROLOG
 WTO "Hello, COR24!\n"
 RETURN 0
COPY svc_bare_code     ; emits only _svc_wto, the one routine used
```

Each member's header comment documents its macros in full. The test
programs in [`demos/libtest/`](../demos/libtest) exercise every macro
(`reg-rs/check_lib.sh`, tests `hlasm_e2e_lib_*`).

### Calling convention

The routines follow tc24r's calling convention, so hlasm routines and
tc24r-compiled ones can call each other:

- the caller pushes the arguments right to left, one word each, and pops
  them after the call; the result comes back in r0;
- the callee saves fp, r2 and r1 (`push fp`/`push r2`/`push r1`/`mov fp,sp`),
  so the first argument is at `9(fp)`, the second at `12(fp)`, and locals
  are below fp;
- r0 and r1 are scratch across a call, r2 and fp are preserved.

Unless a macro says otherwise, it may change r0 and r1 and preserves r2.

### Data placement

cor24-asm has no separate data section: `.data` and `.text` are accepted
but ignored, and bytes land exactly where they are written. Data must
therefore sit where execution never reaches: after a routine's `RET`, or in
a block after the program's routines. The data macros (`STR`, `WORDS`,
`BYTES`, `SPACE`) follow this rule. `WTO` keeps its text inline instead:
it calls `_svc_wto`, which prints the string stored right after the call
and returns past it.

### Members and macros

**`lib/cor24.hlasm`**: board addresses as `EQU`s (no code): `UART_DATA`,
`UART_STATUS`, `UART_TXBUSY`, `UART_RXREADY`, `LED_REG`, `LED_ON`, `LED_OFF`,
`INT_ENABLE`.

**`lib/frame.hlasm`**: routine frames and calls.

| Macro | Does | Registers |
|---|---|---|
| `PROLOG [bytes]` | save fp, r2, r1; `mov fp,sp`; reserve `bytes` of locals (default: the `LOCAL`s declared since the last `PROLOG`) | |
| `RET` | restore and return (result in r0) | |
| `RETURN value` | r0 = value (register, constant, character or label), then `RET` | |
| `ARG reg,n` | reg = the nth argument (1-based) | reg |
| `LOCAL name,bytes` | declare a local before `PROLOG`; `name` becomes its fp offset (`lw r0,name(fp)`) | none |
| `CALL fn[,a1..a8]` | push the arguments right to left, call, pop them; result in r0. fn is a label, r0 or r2 | r0, r1 |
| `LOADR reg,value` | reg = value: `mov` from a register, `la` for anything else | reg |
| `PUSHARG value` | push one argument: a register directly, anything else through r1 | r1 |

`CALL` loads constant and label arguments through r1, so an r1 argument must
have only register arguments to its right. r0 and r2 arguments are always
safe.

**`lib/svc_bare.hlasm`**: the system-services interface, bare-metal target
(routines in `svc_bare_code`). A sw-tos member can later provide the same
macros.

| Macro | Does |
|---|---|
| `START [main]` | program entry: `_start` calls `_main` (or `main`), then `_exit` |
| `EXIT [code]` | from anywhere: r0 = code, jump to `_exit`. With `SET SHOWRC,1`, `_exit` prints `r0=<n>`; then the program halts |
| `PUTC [char]` | write one character (register, default r0, or a constant such as `'A'`), inline |
| `PUTNL` | write a newline |
| `PUTS str` | write the NUL-terminated string at a label or register |
| `WTO "text"` | write a literal string (escapes resolved by hlasm) |
| `PUTDEC [value]` | write a value in signed decimal (default r0) |
| `PUTHEX [value]` | write a value in lower-case hex, no leading zeros (like tc24r's `%x`) |
| `GETC [reg]` | wait for a UART character; r0 (and reg) = it |
| `GETLINE buf,len` | read up to a newline or len-1 characters into buf, NUL-terminated; r0 = length |
| `GETMAIN reg,size` | allocate size bytes (at least 3, rounded up to whole words) from a bump heap at `SVC_HEAP`, 0x080000 by default (like tc24r's `malloc`); reg = address |
| `FREEMAIN reg,size` | no code (a bump allocator does not reclaim, like tc24r's `free`) |

**`lib/board.hlasm`**: `LEDON`, `LEDOFF` (LED D2, active-low) and
`BUTTON [reg]` (bit 0 of the button register: 0 while S2 is pressed). Each
changes r0 and r1.

**`lib/data.hlasm`**: labelled data, placed where the macro is called (see
Data placement); no registers change.

| Macro | Defines |
|---|---|
| `STR label,"text"` | a NUL-terminated string |
| `SPACE label,bytes` | zeroed storage |
| `WORDS label,v1[,...,v8]` | 24-bit words |
| `BYTES label,v1[,...,v8]` | bytes |

**`lib/check.hlasm`**: the self-test pattern of the tiny-C demos.

| Macro | Does |
|---|---|
| `CHECKINIT` | set the ok flag (one word, `_chk_ok`, jumped over); use once per program |
| `CHECK cond,a,b` | clear the flag unless the structured condition holds (`CHECK cc_eq,r0,25` is C's `if (x != 25) ok = 0;`) |
| `CHECKEND "text",rc` | if the flag is set, write text and set r0 = rc; otherwise r0 = 0 |

**`lib/rt.hlasm`** (macros) and **`lib/rt_code.hlasm`** (routines): the C
library routines the demos use, with tc24r's semantics.

| Macro | Does |
|---|---|
| `DIV a,b` / `MOD a,b` | r0 = a / b, a % b, signed, truncating toward zero like C |
| `RTCALL name[,args]` | call `_name` and have `rt_code` emit it: `strlen(s)`, `strcmp(a,b)`, `strcpy(dst,src)`, `memcpy(dst,src,n)`, `memset(s,c,n)`, `atoi(s)` |

## Port plan

Ported demos are added to each group as its step lands.

| Group | Demos |
|---|---|
| A. I/O | uart_tx, hello, led, button, demo2, demo3, demo8, demo10, demo64, demo9 |
| B. Control flow | demo, demo4, demo11, demo12, demo13, demo14, demo15, demo21, demo26, demo46 |
| C. Functions, arrays, pointers, strings | demo5, demo6, demo7, demo16, demo39, demo41, demo50, demo51-54, demo58, demo63 |
| D. Structs, unions, heap | demo23, demo25, demo28, demo34, demo35, demo38, demo40, demo42, demo43 |

The other 26 demos test C syntax that has no assembly counterpart:
typedef, line continuation, prototypes, compound literals, and tc24r
parser regressions. They are not ported. The list and the reasons are
in [tinyc-port-plan.md](tinyc-port-plan.md#demos-to-skip).

## Ported demos

None yet.
