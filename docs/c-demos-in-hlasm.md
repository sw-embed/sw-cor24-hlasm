# The tiny-C demos in hlasm

The C compiler tc24r (`../sw-cor24-x-tinyc`) ships about seventy small
demo programs. This document shows those programs rewritten in hlasm,
side by side with the C, using a shared macro library. The point is to
show what macros buy over writing plain COR24 assembly, and how close
hlasm source can come to the C it replaces.

Status: the macro library is done, and batch 1 (the 10 I/O demos) is
ported; see [Ported demos](#ported-demos). Batches 2-4 follow. The
detailed survey and reasoning are in
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
| `LOCADDR reg,name` | reg = the address of a `LOCAL` (C's `&x`) | reg |
| `ISRENTRY` / `ISRRET` | interrupt handler entry and exit: save and restore r0-r2, the C flag and fp; return with `jmp (ir)` | none |

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
| A. I/O (**ported**) | uart_tx, hello, led, button, demo2, demo3, demo8, demo10, demo64, demo9 |
| B. Control flow | demo, demo4, demo11, demo12, demo13, demo14, demo15, demo21, demo26, demo46 |
| C. Functions, arrays, pointers, strings | demo5, demo6, demo7, demo16, demo39, demo41, demo50, demo51-54, demo58, demo63 |
| D. Structs, unions, heap | demo23, demo25, demo28, demo34, demo35, demo38, demo40, demo42, demo43 |

The other 26 demos test C syntax that has no assembly counterpart:
typedef, line continuation, prototypes, compound literals, and tc24r
parser regressions. They are not ported. The list and the reasons are
in [tinyc-port-plan.md](tinyc-port-plan.md#demos-to-skip).

## Ported demos

### Batch 1: I/O (step 12)

Each entry links the C original and the port. The C is folded and the HLASM
shown in full; line counts are non-blank lines. The output is the
regression test baseline (`reg-rs/hlasm_e2e_tinyc_<demo>.out`): what the
program writes to the UART, then `r0=<n>` (the value main returned), and
for the LED demos the final LED state that cor24-emu reports. Each matches
what the C demo's own run script checks.

### uart_tx: write characters to the UART

[`uart_tx.c`](../../sw-cor24-x-tinyc/demos/uart_tx.c) (12 lines; 71 lines of tc24r assembly) →
[`demos/tinyc/uart_tx.hlasm`](../demos/tinyc/uart_tx.hlasm) (15 lines).
Macros: `START`, `PROLOG`, `PUTC`, `PUTNL`, `RETURN`.

<details><summary>C source</summary>

```c
// Send characters via UART TX
void putc(int c) {
    while (*(char *)0xFF0101 & 0x80) {}
    *(char *)0xFF0100 = c;
}

int main() {
    putc(72);   // 'H'
    putc(105);  // 'i'
    putc(33);   // '!'
    putc(10);   // newline
    return 0;
}
```

</details>

```
; uart_tx.c in hlasm: send "Hi!" and a newline over the UART, return 0.
; Output: "Hi!" then "r0=0".
COPY cor24
COPY frame
COPY svc_bare
SET SHOWRC,1
 START
_main:
 PROLOG
 PUTC 'H'
 PUTC 'i'
 PUTC '!'
 PUTNL
 RETURN 0
COPY svc_bare_code
```

Output:

```
Hi!
r0=0
```

### hello: print a string

[`hello.c`](../../sw-cor24-x-tinyc/demos/hello.c) (15 lines; 91 lines of tc24r assembly) →
[`demos/tinyc/hello.hlasm`](../demos/tinyc/hello.hlasm) (12 lines).
Macros: `START`, `PROLOG`, `WTO`, `RETURN`.

<details><summary>C source</summary>

```c
// Hello World -- string constants + pointer iteration + UART TX

void putc(int c) {
    while (*(char *)0xFF0101 & 0x80) {}
    *(char *)0xFF0100 = c;
}

void puts(char *s) {
    while (*s) {
        putc(*s);
        s = s + 1;
    }
}

int main() {
    puts("Hello, COR24!\n");
    return 0;
}
```

</details>

```
; hello.c in hlasm: print "Hello, COR24!" and return 0.
; Output: "Hello, COR24!" then "r0=0".
COPY cor24
COPY frame
COPY svc_bare
SET SHOWRC,1
 START
_main:
 PROLOG
 WTO "Hello, COR24!\n"
 RETURN 0
COPY svc_bare_code
```

Output:

```
Hello, COR24!
r0=0
```

### led: turn the LED on

[`led.c`](../../sw-cor24-x-tinyc/demos/led.c) (8 lines; no tc24r assembly checked in) →
[`demos/tinyc/led.hlasm`](../demos/tinyc/led.hlasm) (13 lines).
Macros: `LEDON`.

<details><summary>C source</summary>

```c
// Turn on LED D2 (active-low: write 0 to bit 0)
void led_on() {
    *(char *)0xFF0000 = 0;
}

int main() {
    led_on();
    return 0;
}
```

</details>

```
; led.c in hlasm: turn LED D2 on, return 0.
; Output: "r0=0"; cor24-emu reports the LED on.
COPY cor24
COPY frame
COPY svc_bare
COPY board
SET SHOWRC,1
 START
_main:
 PROLOG
 LEDON
 RETURN 0
COPY svc_bare_code
```

Output:

```
r0=0
[LED] 0x00 (D2 on)
```

### button: read the button

[`button.c`](../../sw-cor24-x-tinyc/demos/button.c) (7 lines; no tc24r assembly checked in) →
[`demos/tinyc/button.hlasm`](../demos/tinyc/button.hlasm) (18 lines).
Macros: `CALL`, `BUTTON`, `RET`.

<details><summary>C source</summary>

```c
// Read button S2 state (bit 0: 0=pressed, 1=released)
int button_pressed() {
    return *(char *)0xFF0000 & 1;
}

int main() {
    return button_pressed();
}
```

</details>

```
; button.c in hlasm: return the button S2 bit (0 = pressed, 1 = released).
; Output: "r0=1" when released, "r0=0" when run with --switch on.
COPY cor24
COPY frame
COPY svc_bare
COPY board
SET SHOWRC,1
 START
_main:
 PROLOG
 CALL _button_pressed
 RET

; _button_pressed(): bit 0 of the button register
_button_pressed:
 PROLOG
 BUTTON
 RET
COPY svc_bare_code
```

Output:

```
released: r0=1
pressed: r0=0
```

### demo2: char, pointers to locals, MMIO

[`demo2.c`](../../sw-cor24-x-tinyc/demos/demo2.c) (61 lines; 165 lines of tc24r assembly) →
[`demos/tinyc/demo2.hlasm`](../demos/tinyc/demo2.hlasm) (41 lines).
Macros: `LOCAL`, `LOCADDR`, `CHECKINIT`/`CHECK`/`CHECKEND`, `LEDON`.

<details><summary>C source</summary>

```c
// tc24r demo2 -- Phase 4 features: char, pointers, casts, MMIO
//
// New features since demo.c:
//   - C comments (// and /* */)
//   - char type
//   - pointer declarations (int *, char *)
//   - address-of (&x)
//   - pointer dereference (*p) read and write
//   - cast expressions ((char *)addr)
//   - MMIO: LED D2 control, UART TX output
//
// COR24-TB hardware: 1 LED (D2), 1 button (S2), UART
//   LED at 0xFF0000, active-low: bit 0 = 0 turns LED on, 1 turns off
//   UART data at 0xFF0100
//
// Expected result after execution:
//   r0 = 42
//   LED = 0x00 (D2 on, active-low)
//   UART output: "OK"

/* MMIO helpers */
void led_on() {
    *(char *)0xFF0000 = 0;  /* active-low: 0 = LED on */
}

void led_off() {
    *(char *)0xFF0000 = 1;  /* active-low: 1 = LED off */
}

void uart_putc(int c) {
    while (*(char *)0xFF0101 & 0x80) {}
    *(char *)0xFF0100 = c;
}

int main() {
    int ok = 1;

    // --- char type ---
    char a = 65;
    char b = 66;
    if (a != 65) { ok = 0; }
    if (b != 66) { ok = 0; }

    // --- pointer to int: read via dereference ---
    int x = 123;
    int *px = &x;
    if (*px != 123) { ok = 0; }

    // --- pointer write: modify through pointer ---
    *px = 456;
    if (x != 456) { ok = 0; }

    // --- pointer to char ---
    char ch = 77;
    char *pc = &ch;
    if (*pc != 77) { ok = 0; }

    // --- MMIO: turn on LED D2 ---
    led_on();

    // --- UART output ---
    if (ok == 1) {
        uart_putc(79);   /* 'O' */
        uart_putc(75);   /* 'K' */
        uart_putc(10);   /* newline */
    }

    if (ok == 1) {
        return 42;
    }
    return 0;
}
```

</details>

```
; demo2.c in hlasm: char values, pointers to locals (read and write through
; them), LED on through MMIO; prints "OK" and returns 42 if every check holds.
; Output: "OK" then "r0=42"; cor24-emu reports the LED on.
COPY cor24
COPY frame
COPY svc_bare
COPY board
COPY check
SET SHOWRC,1
 START
_main:
 LOCAL X,3
 LOCAL CH,3
 PROLOG
 CHECKINIT
; char a = 65, b = 66
 lc r0,65
 CHECK cc_eq,r0,65
 lc r0,66
 CHECK cc_eq,r0,66
; int x = 123; int *px = &x;  *px == 123
 la r0,123
 sw r0,X(fp)
 LOCADDR r2,X
 lw r0,0(r2)
 CHECK cc_eq,r0,123
; *px = 456;  x == 456
 la r0,456
 sw r0,0(r2)
 lw r0,X(fp)
 CHECK cc_eq,r0,456
; char ch = 77; char *pc = &ch;  *pc == 77
 lc r0,77
 sb r0,CH(fp)
 LOCADDR r2,CH
 lbu r0,0(r2)
 CHECK cc_eq,r0,77
 LEDON
 CHECKEND "OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
OK
r0=42
[LED] 0x00 (D2 on)
```

### demo3: hex literals, string constant, pointer stepping

[`demo3.c`](../../sw-cor24-x-tinyc/demos/demo3.c) (56 lines; 191 lines of tc24r assembly) →
[`demos/tinyc/demo3.hlasm`](../demos/tinyc/demo3.hlasm) (37 lines).
Macros: `RTCALL strlen`, `STR`, `CHECK`.

<details><summary>C source</summary>

```c
// tc24r demo3 -- hex literals, pointer arithmetic, string constants
//
// New features since demo2:
//   - Hex integer literals (0xFF, 0xFF0100)
//   - Pointer arithmetic (char *p; p + 1 advances 1 byte)
//   - String constants ("Hello" becomes label in .data)
//   - String iteration via pointer + dereference
//
// Expected result:
//   r0 = 42
//   UART output: "D3OK"

void putc(int c) {
    while (*(char *)0xFF0101 & 0x80) {}
    *(char *)0xFF0100 = c;
}

void puts(char *s) {
    while (*s) {
        putc(*s);
        s = s + 1;
    }
}

int strlen(char *s) {
    int n = 0;
    while (*s) {
        n = n + 1;
        s = s + 1;
    }
    return n;
}

int main() {
    int ok = 1;

    // --- hex literals ---
    int a = 0xFF;
    if (a != 255) { ok = 0; }
    int b = 0x2A;
    if (b != 42) { ok = 0; }

    // --- string constant + strlen ---
    char *msg = "Hello";
    int len = strlen(msg);
    if (len != 5) { ok = 0; }

    // --- pointer arithmetic: char * advances by 1 ---
    char *p = msg;
    p = p + 1;
    if (*p != 101) { ok = 0; }  /* 'e' = 101 */

    // --- pointer arithmetic: second char of string ---
    char *q = msg + 4;
    if (*q != 111) { ok = 0; }  /* 'o' = 111 */

    // --- UART output ---
    if (ok == 1) {
        puts("D3OK\n");
    }

    if (ok == 1) {
        return 0x2A;
    }
    return 0;
}
```

</details>

```
; demo3.c in hlasm: hex literals, a string constant, strlen, and stepping a
; char pointer through the string; prints "D3OK" and returns 0x2A.
; Output: "D3OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY data
COPY check
COPY rt
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
; int a = 0xFF; int b = 0x2A;
 la r0,0xFF
 CHECK cc_eq,r0,255
 la r0,0x2A
 CHECK cc_eq,r0,42
; char *msg = "Hello"; strlen(msg) == 5
 RTCALL strlen,msg
 CHECK cc_eq,r0,5
; char *p = msg + 1;  *p == 'e'
 la r2,msg
 add r2,1
 lbu r0,0(r2)
 CHECK cc_eq,r0,101
; char *q = msg + 4;  *q == 'o'
 la r2,msg
 add r2,4
 lbu r0,0(r2)
 CHECK cc_eq,r0,111
 CHECKEND "D3OK\n",0x2A
 RET
 STR msg,"Hello"
COPY svc_bare_code
COPY rt_code
```

Output:

```
D3OK
r0=42
```

### demo8: #define constants as EQU

[`demo8.c`](../../sw-cor24-x-tinyc/demos/demo8.c) (49 lines; 159 lines of tc24r assembly) →
[`demos/tinyc/demo8.hlasm`](../demos/tinyc/demo8.hlasm) (34 lines).
Macros: `EQU`, `LEDON`, `RTCALL strlen`, `CHECK`.

<details><summary>C source</summary>

```c
// tc24r demo8 -- preprocessor #define
//
// New features:
//   - #define NAME value (constant substitution)
//   - Substitution skips string literals
//   - No partial identifier matching (FOO does not match FOOBAR)
//
// Expected: r0 = 42, LED D2 on, UART output: "D8OK"

#define LED_REG      0xFF0000
#define UART_REG     0xFF0100
#define UART_STATUS  0xFF0101
#define LED_ON       0
#define ANSWER    42
#define GREETING  "D8OK\n"

void led_on() {
    *(char *)LED_REG = LED_ON;
}

void putc(int c) {
    while (*(char *)UART_STATUS & 0x80) {}
    *(char *)UART_REG = c;
}

void puts(char *s) {
    while (*s) {
        putc(*s);
        s = s + 1;
    }
}

int main() {
    int ok = 1;

    // #define constants in expressions
    int a = ANSWER;
    if (a != 42) { ok = 0; }

    // #define in MMIO
    led_on();

    // #define does not substitute inside strings
    char *msg = "ANSWER is not replaced here";
    int len = 0;
    char *p = msg;
    while (*p) { len = len + 1; p = p + 1; }
    if (len != 27) { ok = 0; }

    // #define with no partial match
    int ANSWERING = 99;
    if (ANSWERING != 99) { ok = 0; }

    if (ok == 1) {
        puts(GREETING);
        return ANSWER;
    }
    return 0;
}
```

</details>

```
; demo8.c in hlasm: #define constants become EQU symbols, used in
; instructions, MMIO and compares; prints "D8OK" and returns ANSWER (42).
; Output: "D8OK" then "r0=42"; cor24-emu reports the LED on.
; (hlasm has no string-valued symbols, so GREETING is written out.)
COPY cor24
COPY frame
COPY svc_bare
COPY board
COPY data
COPY check
COPY rt
ANSWER EQU 42
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
; int a = ANSWER;
 la r0,ANSWER
 CHECK cc_eq,r0,42
; led_on() writes LED_ON to LED_REG
 LEDON
; the symbol is not replaced inside a string: strlen is 27
 RTCALL strlen,msg
 CHECK cc_eq,r0,27
; ANSWERING is a different name from ANSWER
ANSWERING EQU 99
 la r0,ANSWERING
 CHECK cc_eq,r0,99
 CHECKEND "D8OK\n",ANSWER
 RET
 STR msg,"ANSWER is not replaced here"
COPY svc_bare_code
COPY rt_code
```

Output:

```
D8OK
r0=42
[LED] 0x00 (D2 on)
```

### demo10: #include as COPY, with an include guard

[`demo10.c`](../../sw-cor24-x-tinyc/demos/demo10.c) (26 lines; 125 lines of tc24r assembly) →
[`demos/tinyc/demo10.hlasm`](../demos/tinyc/demo10.hlasm) (32 lines).
Macros: `COPY`, `IFNDEF`/`SET` guard, `CALL`, `PUTC`, `LEDON`.

<details><summary>C source</summary>

```c
// tc24r demo10 -- #include, #pragma once, system header
//
// New features:
//   - #include "file.h" (relative to source file)
//   - #include <cor24.h> (system include path via -I)
//   - #pragma once (prevents double inclusion)
//   - -I flag for include search paths
//
// Expected: r0 = 42, LED D2 on, UART output: "D10OK"

#include "demo10_io.h"
#include "demo10_io.h"
#include <cor24.h>

int main() {
    int ok = 1;

    // Verify #define from local header
    if (LED_REG != 0xFF0000) { ok = 0; }

    // Verify #define from system header (cor24.h)
    if (UART_STATUS != 0xFF0101) { ok = 0; }

    // Use functions from included header
    led_on();

    if (ok == 1) {
        puts("D10OK\n");
        return 42;
    }
    return 0;
}

// --- demo10_io.h ---
#pragma once

#define LED_REG     0xFF0000
#define UART_DATA   0xFF0100
#define UART_STATUS 0xFF0101
#define INT_ENABLE  0xFF0010
#define LED_ON      0

void putc(int c) {
    while (*(char *)UART_STATUS & 0x80) {}
    *(char *)UART_DATA = c;
}

void puts(char *s) {
    while (*s) {
        putc(*s);
        s = s + 1;
    }
}

void led_on() {
    *(char *)LED_REG = LED_ON;
}
```

</details>

```
; demo10.c in hlasm: #include becomes COPY. The board constants come from
; the library member cor24 (as <cor24.h>), the routines from the
; demo-local member demo10_io (as "demo10_io.h"), COPYed twice to show
; its guard. Prints "D10OK" and returns 42.
; Output: "D10OK" then "r0=42"; cor24-emu reports the LED on.
COPY cor24
COPY frame
COPY svc_bare
COPY board
COPY data
COPY check
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
 la r0,LED_REG
 CHECK cc_eq,r0,0xFF0000
 la r0,UART_STATUS
 CHECK cc_eq,r0,0xFF0101
 CALL _led_on
 la r1,_chk_ok
 lw r0,0(r1)
IF cc_ne,r0,0
 CALL _puts,msg
 RETURN 42
ENDIF
 RETURN 0
 STR msg,"D10OK\n"
COPY demo10_io
COPY demo10_io
COPY svc_bare_code

; --- demo10_io.hlasm ---
; demo10_io.hlasm: the port of demo10_io.h, a member with an include guard
; (as #pragma once). It holds routines, so it is COPYed after the program's
; own code; COPYing it twice emits it once.
IFNDEF DEMO10_IO
SET DEMO10_IO,1
; _puts(s): write a NUL-terminated string
_puts:
 PROLOG
 ARG r2,1
DO
 lbu r0,0(r2)
 DOEXIT cc_eq,r0,0
 PUTC
 add r2,1
ENDDO
 RET

; _led_on(): LED D2 on
_led_on:
 PROLOG
 LEDON
 RET
ENDIFASM
```

Output:

```
D10OK
r0=42
[LED] 0x00 (D2 on)
```

### demo9: UART receive interrupt

[`demo9.c`](../../sw-cor24-x-tinyc/demos/demo9.c) (27 lines; 61 lines of tc24r assembly) →
[`demos/tinyc/demo9.hlasm`](../demos/tinyc/demo9.hlasm) (34 lines).
Macros: `ISRENTRY`/`ISRRET`, `WORDS`, `DO`/`DOEXIT`.

<details><summary>C source</summary>

```c
// tc24r demo9 -- UART RX interrupt
//
// New features:
//   - __attribute__((interrupt)) ISR with automatic prologue/epilogue
//   - Interrupt vector setup via asm()
//   - MMIO interrupt enable
//   - Polling a global set by ISR
//
// Expected: r0 = received UART character (0x41 = 'A' when --uart-input "A")

#define UART_DATA   0xFF0100
#define UART_STATUS 0xFF0101
#define INT_ENABLE  0xFF0010

int rx_char = 0;

__attribute__((interrupt))
void uart_isr() {
    // Read UART data register (clears interrupt)
    rx_char = *(char *)UART_DATA;
}

int main() {
    // Set interrupt vector to uart_isr
    asm("la r0,_uart_isr\nmov iv,r0");

    // Enable UART RX interrupt
    *(char *)INT_ENABLE = 1;

    // Poll until ISR sets rx_char
    while (rx_char == 0) {}

    return rx_char;
}
```

</details>

```
; demo9.c in hlasm: a UART receive interrupt handler stores the received
; character; main installs it, enables the interrupt and waits for it.
; Run with UART input "A". Output: "r0=65".
COPY cor24
COPY frame
COPY svc_bare
COPY data
SET SHOWRC,1
 START
_main:
 PROLOG
; install the handler and enable the UART RX interrupt
 la r0,_uart_isr
 mov iv,r0
 la r1,INT_ENABLE
 lc r0,1
 sb r0,0(r1)
; wait until the handler has stored a character
DO
 la r1,_rx_char
 lw r0,0(r1)
 DOEXIT cc_ne,r0,0
ENDDO
 RET

; the handler: reading the data register clears the interrupt
_uart_isr:
 ISRENTRY
 la r1,UART_DATA
 lbu r0,0(r1)
 la r1,_rx_char
 sw r0,0(r1)
 ISRRET
 WORDS _rx_char,0
COPY svc_bare_code
```

Output:

```
r0=65
```

### demo64: no library: fill a buffer and count

[`demo64.c`](../../sw-cor24-x-tinyc/demos/demo64.c) (32 lines; no tc24r assembly checked in) →
[`demos/tinyc/demo64.hlasm`](../demos/tinyc/demo64.hlasm) (38 lines).
Macros: a demo-local `COUNTIF` macro, `SPACE`, `RETURN`.

<details><summary>C source</summary>

```c
// tc24r demo64 -- no-std minimal: copy "hello" to memory and halt.
//
// No #include directives. Nothing from <stdio.h>, <stdlib.h>, <string.h>.
// This is the smallest possible program that proves the DCE pass
// produces a clean `.s` when nothing is needed:
//   - no _abs, _atoi, _malloc, _free, _printf*, _strcmp, ...
//   - just _start, _halt, _main, the data symbol for the buffer,
//     and any codegen-emitted helpers actually used (none here).
//
// The 'expected r0' is just sizeof("hello") (5 chars) so we can
// verify it ran. The runner script also checks that DCE has
// trimmed the symbol table.
//
// Expected: r0 = 5

char buf[5];

int main(void) {
    buf[0] = 'h';
    buf[1] = 'e';
    buf[2] = 'l';
    buf[3] = 'l';
    buf[4] = 'o';

    /* Sum-of-indices proof we wrote each byte by referring to the
       global location, not by short-circuiting. Result is just
       a witness — meaningful number is buf[0]..[4] vs 'h'..'o'. */
    int n = 0;
    if (buf[0] == 'h') n = n + 1;
    if (buf[1] == 'e') n = n + 1;
    if (buf[2] == 'l') n = n + 1;
    if (buf[3] == 'l') n = n + 1;
    if (buf[4] == 'o') n = n + 1;
    return n; /* 5 */
}
```

</details>

```
; demo64.c in hlasm: write "hello" into a 5-byte global buffer, then count
; the bytes that match; returns 5. A demo-local macro does each count.
; Output: "r0=5". (Without SHOWRC no library routine at all would be
; emitted -- the counterpart of tc24r's dead-code check.)
COPY cor24
COPY frame
COPY svc_bare
COPY data
SET SHOWRC,1

; COUNTIF n,ch: add 1 to r2 if buf[n] is ch
MACRO COUNTIF &N,&C
 lbu r0,&N(r1)
IF cc_eq,r0,&C
 add r2,1
ENDIF
MEND

 START
_main:
 PROLOG
 la r1,buf
 lc r0,'h'
 sb r0,0(r1)
 lc r0,'e'
 sb r0,1(r1)
 lc r0,'l'
 sb r0,2(r1)
 sb r0,3(r1)
 lc r0,'o'
 sb r0,4(r1)
 lc r2,0
 COUNTIF 0,'h'
 COUNTIF 1,'e'
 COUNTIF 2,'l'
 COUNTIF 3,'l'
 COUNTIF 4,'o'
 RETURN r2
 SPACE buf,5
COPY svc_bare_code
```

Output:

```
r0=5
```

