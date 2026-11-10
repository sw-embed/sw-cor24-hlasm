# The tiny-C demos in hlasm

The C compiler tc24r (`../sw-cor24-x-tinyc`) ships about seventy small
demo programs. This document shows those programs rewritten in hlasm,
side by side with the C, using a shared macro library. The point is to
show what macros buy over writing plain COR24 assembly, and how close
hlasm source can come to the C it replaces.

Status: the macro library is done, and all four batches are ported: 42
demos (10 I/O, 10 control flow, 13 functions and data, 9 structs, unions
and heap), plus a second demo11 using AND/OR; see
[Ported demos](#ported-demos). [What the macros buy](#what-the-macros-buy-hlasm-against-tc24r)
compares every port with tc24r's output; `./demo.sh c-demos` runs them all.
The detailed survey and reasoning are in
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
| `LOCADDR reg,name` | reg (r0 or r2) = the address of a `LOCAL` (C's `&x`), at any depth | reg, r1 |
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
| `REQUIRE cond,a,b,rc` | return rc from the current routine unless the condition holds (C's `if (x != 7) return 1;`) |

**`lib/struct.hlasm`**: record layouts (C's struct and union), no code.

| Macro | Does |
|---|---|
| `DSECT name` / `USECT name` | start a struct / union layout |
| `FIELD name,bytes` | the next member: `name` = its offset (in a union, 0); bytes is an expression |
| `DEND name` | end the layout; `SIZEOF_name` = its size |

Misuse stops with an `ERROR` (raised with hlasm's `ERROR 'message'` directive).
Prefix field names per record, since they are global symbols.

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
| B. Control flow (**ported**) | demo, demo4, demo11 (and demo11_andor), demo12, demo13, demo14, demo15, demo21, demo26, demo46 |
| C. Functions, arrays, pointers, strings (**ported**) | demo5, demo6, demo7, demo16, demo39, demo41, demo50, demo51-54, demo58, demo63 |
| D. Structs, unions, heap (**ported**) | demo23, demo25, demo28, demo34, demo35, demo38, demo40, demo42, demo43 |

The other 26 demos test C syntax that has no assembly counterpart:
typedef, line continuation, prototypes, compound literals, and tc24r
parser regressions. They are not ported. The list and the reasons are
in [tinyc-port-plan.md](tinyc-port-plan.md#demos-to-skip).

## What the macros buy: hlasm against tc24r

`scripts/c-demos.sh --table` compares every port with tc24r's compiled
version of the same C program. Source lines are non-blank, non-comment
lines. `.s` lines are instruction and data lines (not labels, comments or
section directives). Bytes are the assembled code and data. Executed is the
number of instructions cor24-emu runs to the halt. The hlasm versions are
measured without their `r0=` report, so both do the same work. A `-` means
tc24r's `.s` is not checked in for that demo.

| Demo | C lines | HLASM lines | tc24r .s lines | hlasm .s lines | tc24r bytes | hlasm bytes | tc24r executed | hlasm executed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| button | 6 | 15 | - | 27 | - | 39 | - | 26 |
| demo | 51 | 82 | 212 | 210 | 367 | 372 | 840 | 798 |
| demo10 | 14 | 27 | 100 | 101 | 180 | 187 | 265 | 163 |
| demo11_andor | 20 | 33 | 166 | 161 | 285 | 283 | 305 | 201 |
| demo11 | 20 | 45 | 166 | 225 | 285 | 418 | 305 | 251 |
| demo12 | 27 | 30 | 117 | 105 | 208 | 194 | 309 | 193 |
| demo13 | 37 | 64 | 200 | 320 | 350 | 555 | 1033 | 5356 |
| demo14 | 26 | 33 | 176 | 141 | 298 | 260 | 393 | 226 |
| demo15 | 26 | 58 | 200 | 202 | 334 | 359 | 367 | 260 |
| demo16 | 21 | 28 | 122 | 141 | 217 | 265 | 275 | 185 |
| demo2 | 31 | 34 | 140 | 126 | 245 | 243 | 151 | 137 |
| demo21 | 35 | 45 | 219 | 332 | 382 | 585 | 397 | 863 |
| demo23 | 22 | 44 | 116 | 119 | 206 | 235 | 273 | 171 |
| demo25 | 30 | 49 | 173 | 134 | 284 | 255 | 330 | 186 |
| demo26 | 72 | 78 | 370 | 296 | 564 | 528 | 710 | 424 |
| demo28 | 25 | 37 | 159 | 104 | 244 | 201 | 360 | 164 |
| demo3 | 39 | 30 | 159 | 140 | 288 | 265 | 339 | 217 |
| demo34 | 24 | 35 | 234 | 112 | 346 | 218 | 435 | 172 |
| demo35 | 25 | 30 | 128 | 89 | 200 | 172 | 331 | 153 |
| demo38 | 21 | 48 | 204 | 125 | 307 | 249 | 403 | 181 |
| demo39 | 12 | 14 | 1091 | 168 | 1834 | 320 | 977 | 329 |
| demo4 | 25 | 26 | 202 | 337 | 345 | 620 | 895 | 2824 |
| demo40 | 24 | 41 | 1453 | 197 | 2372 | 355 | 991 | 395 |
| demo41 | 22 | 44 | 2229 | 371 | 3695 | 677 | 1952 | 882 |
| demo42 | 31 | 52 | 1613 | 135 | 2624 | 244 | 596 | 222 |
| demo43 | 36 | 76 | 1728 | 245 | 2813 | 441 | 1542 | 825 |
| demo46 | 43 | 34 | 242 | 150 | 426 | 292 | 427 | 190 |
| demo5 | 40 | 56 | 246 | 150 | 389 | 276 | 449 | 237 |
| demo50 | 27 | 72 | 970 | 331 | 1687 | 562 | 31017 | 181968 |
| demo51 | 14 | 26 | 850 | 93 | 1470 | 159 | 328 | 170 |
| demo52 | 32 | 73 | 1012 | 195 | 1715 | 317 | 574 | 319 |
| demo53 | 20 | 37 | 899 | 144 | 1550 | 236 | 408 | 246 |
| demo54 | 18 | 37 | - | 109 | - | 186 | - | 173 |
| demo58 | 43 | 90 | 1200 | 365 | 2094 | 600 | 603 | 304 |
| demo6 | 28 | 39 | 126 | 124 | 253 | 252 | 248 | 162 |
| demo63 | 30 | 80 | - | 386 | - | 650 | - | 639 |
| demo64 | 17 | 33 | - | 65 | - | 111 | - | 58 |
| demo7 | 40 | 42 | 240 | 285 | 397 | 497 | 417 | 556 |
| demo8 | 35 | 26 | 130 | 117 | 255 | 239 | 600 | 378 |
| demo9 | 13 | 28 | 47 | 46 | 81 | 76 | 10035 | 10036 |
| hello | 13 | 10 | 72 | 38 | 126 | 73 | 619 | 237 |
| led | 6 | 11 | - | 16 | - | 28 | - | 15 |
| uart_tx | 10 | 13 | 59 | 45 | 99 | 88 | 129 | 62 |

Over the 38 demos with both versions:

- **Code size: 12,168 bytes against 29,815 (41%).**
  - From demo39 on, tc24r includes its whole `<stdio.h>`/`<stdlib.h>`
    library in every program that names a header, so demo41 is 3,695 bytes
    against 677.
  - The library's code members emit only the routines a program calls (the
    `IFDEF NEED_<name>` pattern), and a macro such as `PUTC` costs 7
    instructions inline instead of a call to a 25-instruction routine.
- **Instructions executed: lower in 32 of the 38.** tc24r pushes and pops
  around every constant it loads and turns every comparison into 0 or 1
  before testing it. The structured macros compare and branch directly, so
  hello runs in 237 instructions against 619 and demo34 in 172 against 435.
- **The exception is division.** (demo9 is the sixth that is not faster: it
  waits for an interrupt, and the two versions differ by one instruction.)
  demo4, demo7, demo13, demo21 and demo50 run 1.3-6x longer:
  - tc24r divides by repeated subtraction. That is fast for small quotients,
    but it returns 0 for a negative dividend (`-17 / 5` gives 0, not -3).
  - The library's `DIV`/`MOD` are correct for every signed 24-bit value
    (shift and subtract, 24 steps at most, with leading zero bits skipped),
    and that costs a few hundred instructions per call.
  - demo50 calls `MOD` 512 times, so it alone makes the total executed count
    210,643 against 60,628. Without demo50 the hlasm versions run fewer
    instructions in total (28,675 against 29,611).
- **Source lines: HLASM is 0.7-2.7x the C.** About a third of the ports
  are within a third of the C, and several are shorter (demo3, demo8, demo46). The longer ones spell out what C hides: one load per
  operand, a register per variable, the layout of each local.

### Side by side: hello

The C:

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

The HLASM port, the whole program:

```
; hello.c in hlasm: print "Hello, COR24!" and return 0.
; Output: "Hello, COR24!" then "r0=0".
COPY cor24
COPY frame
COPY svc_bare
 START
_main:
 PROLOG
 WTO "Hello, COR24!\n"
 RETURN 0
COPY svc_bare_code
```

hlasm's output is 38 instruction and data lines and 73 bytes. tc24r's is
72 lines and 126 bytes, because `putc` and `puts` are full
routines with frames, and every constant is pushed and popped.

<details><summary>hlasm output</summary>

```
_start:
 la r0,_main
 jal r1,(r0)
_exit:
_halt:
 bra _halt
_main:
 push fp
 push r2
 push r1
 mov fp,sp
 la r0,_svc_wto
 jal r1,(r0)
.byte 72,101,108,108,111,44,32,67,79,82,50,52,33,10
 .byte 0
 la r0,0
 mov sp,fp
 pop r1
 pop r2
 pop fp
 jmp (r1)
_svc_wto:
 push r2
 mov r2,r1
_hldo_1_top:
 lbu r0,0(r2)
 add r2,1
 push r2
 lc r2,0
 ceq r0,r2
 pop r2
 brf _hldo_3_skip
 bra _hldo_2_end
_hldo_3_skip:
 push r2
 la r2,-65280
L0008:
 lb r1,1(r2)
 cls r1,z
 brt L0008
 sb r0,0(r2)
 pop r2
 bra _hldo_1_top
_hldo_2_end:
 mov r1,r2
 pop r2
 jmp (r1)
```

</details>

<details><summary>tc24r output</summary>

```
        .text

        .globl  _start
_start:
        la      r0,_main
        jal     r1,(r0)
_halt:
        bra     _halt

        .globl  _putc
_putc:
        push    fp
        push    r2
        push    r1
        mov     fp,sp
L1:
        la      r0,16711937
        lbu     r0,0(r0)
        push    r0
        la      r0,128
        mov     r1,r0
        pop     r0
        and     r0,r1
        ceq     r0,z
        brt     L2
        bra     L1
L2:
        lw      r0,9(fp)
        push    r0
        la      r0,16711936
        mov     r1,r0
        pop     r0
        sb      r0,0(r1)
L0:
        mov     sp,fp
        pop     r1
        pop     r2
        pop     fp
        jmp     (r1)

        .globl  _puts
_puts:
        push    fp
        push    r2
        push    r1
        mov     fp,sp
L4:
        lw      r0,9(fp)
        lbu     r0,0(r0)
        ceq     r0,z
        brt     L5
        lw      r0,9(fp)
        lbu     r0,0(r0)
        push    r0
        la      r0,_putc
        jal     r1,(r0)
        add     sp,3
        lw      r0,9(fp)
        push    r0
        lc      r0,1
        mov     r1,r0
        pop     r0
        add     r0,r1
        sw      r0,9(fp)
        bra     L4
L5:
L3:
        mov     sp,fp
        pop     r1
        pop     r2
        pop     fp
        jmp     (r1)

        .globl  _main
_main:
        push    fp
        push    r2
        push    r1
        mov     fp,sp
        la      r0,_S0
        push    r0
        la      r0,_puts
        jal     r1,(r0)
        add     sp,3
        lc      r0,0
        bra     L6
L6:
        mov     sp,fp
        pop     r1
        pop     r2
        pop     fp
        jmp     (r1)

        .data
_S0:
        .byte   72,101,108,108,111,44,32,67,79,82,50,52,33,10,0
```

</details>

### Side by side: break and continue (demo13)

The loops of demo13.c are `DO`/`DOEXIT`/`ITERATE`; the source is in the
[demo13 entry](#demo13-break-and-continue) below. Here the hlasm output is
longer than tc24r's (320 lines against 200, 555 bytes against 350), and the
reasons are instructive:

- every `MOD r2,2` is a call to the general signed divide, where tc24r calls
  its short `__tc24r_mod`;
- each compare with a constant saves and restores a scratch register
  (`push r2`/`lc r2,n`/`pop r2`) so that the generated code changes no
  register the program uses.

Both are visible in the output:

<details><summary>hlasm output</summary>

```
_start:
 la r0,_main
 jal r1,(r0)
_exit:
_halt:
 bra _halt
_main:
 push fp
 push r2
 push r1
 mov fp,sp
 sub sp,3
 bra CK0005
_chk_ok:
 .word 0
CK0005:
 la r1,_chk_ok
 lc r0,1
 sw r0,0(r1)
 lc r2,0
_hldo_1_top:
 push r1
 lc r1,5
 ceq r1,r2
 pop r1
 brt _hlif_5_skip
 bra _hlif_3_false
_hlif_5_skip:
 bra _hldo_2_end
_hlif_3_false:
_hlif_4_end:
 add r2,1
 bra _hldo_1_top
_hldo_2_end:
 push r1
 lc r1,5
 ceq r1,r2
 pop r1
 brt _hlif_8_skip
 bra _hlif_6_false
_hlif_8_skip:
 bra _hlif_7_end
_hlif_6_false:
 la r1,_chk_ok
 lc r0,0
 sw r0,0(r1)
_hlif_7_end:
 lc r0,0
 sw r0,-3(fp)
 lc r2,0
 bra _hldo_9_top
_hldo_9_top_far:
 pop r2
_hldo_9_top:
 push r1
 lc r1,10
 cls r2,r1
 pop r1
 brt _hldo_11_skip
 push r2
 la r2,_hldo_10_end_far
 jmp (r2)
_hldo_11_skip:
 add r2,1
 la r1,2
 push r1
 push r2
 la r0,_mod
 jal r1,(r0)
 add sp,6
 push r2
 lc r2,0
 ceq r0,r2
 pop r2
 brt _hlif_14_skip
 bra _hlif_12_false
_hlif_14_skip:
 bra _hldo_9_top
_hlif_12_false:
_hlif_13_end:
 lw r0,-3(fp)
 add r0,r2
 sw r0,-3(fp)
 push r2
 la r2,_hldo_9_top_far
 jmp (r2)
 bra _hldo_10_end
_hldo_10_end_far:
 pop r2
_hldo_10_end:
 lw r0,-3(fp)
 push r2
 lc r2,25
 ceq r0,r2
 pop r2
 brt _hlif_17_skip
 bra _hlif_15_false
_hlif_17_skip:
 bra _hlif_16_end
_hlif_15_false:
 la r1,_chk_ok
 lc r0,0
 sw r0,0(r1)
_hlif_16_end:
 lc r2,0
_hldo_18_top:
 push r1
 lc r1,100
 cls r2,r1
 pop r1
 brt _hldo_20_skip
 bra _hldo_19_end
_hldo_20_skip:
 push r1
 lc r1,3
 ceq r1,r2
 pop r1
 brt _hlif_23_skip
 bra _hlif_21_false
_hlif_23_skip:
 bra _hldo_19_end
_hlif_21_false:
_hlif_22_end:
 add r2,1
 bra _hldo_18_top
_hldo_19_end:
 push r1
 lc r1,3
 ceq r1,r2
 pop r1
 brt _hlif_26_skip
 bra _hlif_24_false
_hlif_26_skip:
 bra _hlif_25_end
_hlif_24_false:
 la r1,_chk_ok
 lc r0,0
 sw r0,0(r1)
_hlif_25_end:
 lc r0,0
 sw r0,-3(fp)
 lc r2,0
 bra _hldo_27_top
_hldo_27_top_far:
 pop r2
_hldo_27_top:
 add r2,1
 push r1
 lc r1,5
 cls r1,r2
 pop r1
 brf _hldo_29_skip
 bra _hldo_28_end
_hldo_29_skip:
 la r1,2
 push r1
 push r2
 la r0,_mod
 jal r1,(r0)
 add sp,6
 push r2
 lc r2,0
 ceq r0,r2
 pop r2
 brt _hlif_32_skip
 bra _hlif_30_false
_hlif_32_skip:
 bra _hldo_27_top
_hlif_30_false:
_hlif_31_end:
 lw r0,-3(fp)
 add r0,r2
 sw r0,-3(fp)
 push r2
 la r2,_hldo_27_top_far
 jmp (r2)
_hldo_28_end:
 lw r0,-3(fp)
 push r2
 lc r2,9
 ceq r0,r2
 pop r2
 brt _hlif_35_skip
 bra _hlif_33_false
_hlif_35_skip:
 bra _hlif_34_end
_hlif_33_false:
 la r1,_chk_ok
 lc r0,0
 sw r0,0(r1)
_hlif_34_end:
 la r1,_chk_ok
 lw r0,0(r1)
 push r2
 lc r2,0
 ceq r0,r2
 pop r2
 brf _hlif_38_skip
 bra _hlif_36_false
_hlif_38_skip:
 la r0,_svc_wto
 jal r1,(r0)
.byte 68,49,51,79,75,10
 .byte 0
 la r0,42
 bra _hlif_37_end
_hlif_36_false:
 lc r0,0
_hlif_37_end:
 mov sp,fp
 pop r1
 pop r2
 pop fp
 jmp (r1)
_svc_wto:
 push r2
 mov r2,r1
_hldo_39_top:
 lbu r0,0(r2)
 add r2,1
 push r2
 lc r2,0
 ceq r0,r2
 pop r2
 brf _hldo_41_skip
 bra _hldo_40_end
_hldo_41_skip:
 push r2
 la r2,-65280
L0024:
 lb r1,1(r2)
 cls r1,z
 brt L0024
 sb r0,0(r2)
 pop r2
 bra _hldo_39_top
_hldo_40_end:
 mov r1,r2
 pop r2
 jmp (r1)
_mod:
 push fp
 push r2
 push r1
 mov fp,sp
 lw r0,9(fp)
 lw r2,12(fp)
 push r2
 push r0
 la r0,_rt_sdivmod
 jal r1,(r0)
 add sp,6
 la r1,_rt_rem
 lw r0,0(r1)
 mov sp,fp
 pop r1
 pop r2
 pop fp
 jmp (r1)
_rt_sdivmod:
 push fp
 push r2
 push r1
 mov fp,sp
 sub sp,6
 lc r0,0
 sw r0,-3(fp)
 sw r0,-6(fp)
 lw r2,9(fp)
 push r1
 lc r1,0
 cls r2,r1
 pop r1
 brt _hlif_44_skip
 bra _hlif_42_false
_hlif_44_skip:
 lc r0,0
 sub r0,r2
 mov r2,r0
 lc r0,1
 sw r0,-3(fp)
 sw r0,-6(fp)
_hlif_42_false:
_hlif_43_end:
 lw r1,12(fp)
 push r2
 lc r2,0
 cls r1,r2
 pop r2
 brt _hlif_47_skip
 bra _hlif_45_false
_hlif_47_skip:
 lc r0,0
 sub r0,r1
 mov r1,r0
 lw r0,-3(fp)
 push r1
 lc r1,1
 xor r0,r1
 pop r1
 sw r0,-3(fp)
_hlif_45_false:
_hlif_46_end:
 push r1
 push r2
 la r0,_rt_udivmod
 jal r1,(r0)
 add sp,6
 lw r1,-3(fp)
 push r2
 lc r2,0
 ceq r1,r2
 pop r2
 brf _hlif_50_skip
 bra _hlif_48_false
_hlif_50_skip:
 lc r1,0
 sub r1,r0
 mov r0,r1
_hlif_48_false:
_hlif_49_end:
 sw r0,-3(fp)
 lw r1,-6(fp)
 push r2
 lc r2,0
 ceq r1,r2
 pop r2
 brf _hlif_53_skip
 bra _hlif_51_false
_hlif_53_skip:
 la r1,_rt_rem
 lw r2,0(r1)
 lc r0,0
 sub r0,r2
 sw r0,0(r1)
_hlif_51_false:
_hlif_52_end:
 lw r0,-3(fp)
 mov sp,fp
 pop r1
 pop r2
 pop fp
 jmp (r1)
_rt_udivmod:
 push fp
 push r2
 push r1
 mov fp,sp
 sub sp,3
 lw r2,9(fp)
 lc r0,24
 sw r0,-3(fp)
_rt_ud_skip:
 cls r2,z
 brt _rt_ud_go
 lw r0,-3(fp)
 ceq r0,z
 brt _rt_ud_go
 add r0,-1
 sw r0,-3(fp)
 add r2,r2
 bra _rt_ud_skip
_rt_ud_go:
 lc r0,0
_rt_ud_loop:
 lw r1,-3(fp)
 ceq r1,z
 brt _rt_ud_done
 add r1,-1
 sw r1,-3(fp)
 add r0,r0
 cls r2,z
 brf _rt_ud_nobit
 add r0,1
_rt_ud_nobit:
 add r2,r2
 lw r1,12(fp)
 clu r0,r1
 brt _rt_ud_loop
 sub r0,r1
 add r2,1
 bra _rt_ud_loop
_rt_ud_done:
 la r1,_rt_rem
 sw r0,0(r1)
 mov r0,r2
 mov sp,fp
 pop r1
 pop r2
 pop fp
 jmp (r1)
_rt_rem:
 .word 0
```

</details>

### Side by side: cons cells (demo43)

The C routine:

```c
struct val *cons(struct val *a, struct val *d) {
    struct val *v = (struct val *)malloc(12);
    v->tag = 1;
    v->car = a;
    v->cdr = d;
    return v;
}
```

The HLASM routine, with the layout declared once (`DSECT cell`):

```
_cons:
 PROLOG
 GETMAIN r2,SIZEOF_cell
 lc r0,1
 sw r0,v_tag(r2)
 ARG r0,1
 sw r0,v_car(r2)
 ARG r0,2
 sw r0,v_cdr(r2)
 RETURN r2
```

It expands to 22 instructions. tc24r's `_cons` is 45:

<details><summary>hlasm output of _cons</summary>

```
_cons:
 push fp
 push r2
 push r1
 mov fp,sp
 la r1,12
 push r1
 la r0,_svc_getmain
 jal r1,(r0)
 add sp,3
 mov r2,r0
 lc r0,1
 sw r0,0(r2)
 lw r0,9(fp)
 sw r0,6(r2)
 lw r0,12(fp)
 sw r0,9(r2)
 mov r0,r2
 mov sp,fp
 pop r1
 pop r2
 pop fp
 jmp (r1)
```

</details>

<details><summary>tc24r output of _cons</summary>

```
_cons:
        push    fp
        push    r2
        push    r1
        mov     fp,sp
        add     sp,-3
        lc      r0,12
        push    r0
        la      r0,_malloc
        jal     r1,(r0)
        add     sp,3
        sw      r0,-3(fp)
        lc      r0,1
        push    r0
        lw      r0,-3(fp)
        mov     r1,r0
        pop     r0
        sw      r0,0(r1)
        lw      r0,9(fp)
        push    r0
        lw      r0,-3(fp)
        push    r0
        lc      r0,6
        pop     r1
        add     r0,r1
        mov     r1,r0
        pop     r0
        sw      r0,0(r1)
        lw      r0,12(fp)
        push    r0
        lw      r0,-3(fp)
        push    r0
        lc      r0,9
        pop     r1
        add     r0,r1
        mov     r1,r0
        pop     r0
        sw      r0,0(r1)
        lw      r0,-3(fp)
        la      r2,L157
        jmp     (r2)
L157:
        mov     sp,fp
        pop     r1
        pop     r2
        pop     fp
        jmp     (r1)
```

</details>

### Every macro and where the ports use it

Counted from `demos/tinyc/*.hlasm` (direct calls; demo4 also calls `DIV` and
`MOD` through a local macro). `EXIT`, `PUTS`, `PUTHEX`, `GETC` and `GETLINE`
are exercised by the library tests in `demos/libtest/` only.

| Macro | Member | Ports | Used by |
|---|---|---:|---|
| `START svc_bare` |  | 0 |  |
| `PROLOG frame` |  | 0 |  |
| `RET frame` |  | 0 |  |
| `RETURN frame` |  | 0 |  |
| `ARG frame` |  | 0 |  |
| `LOCAL frame` |  | 0 |  |
| `LOCADDR frame` |  | 0 |  |
| `CALL frame` |  | 0 |  |
| `ISRENTRY frame` |  | 0 |  |
| `PUTC svc_bare` |  | 0 |  |
| `PUTNL svc_bare` |  | 0 |  |
| `WTO svc_bare` |  | 0 |  |
| `PUTDEC svc_bare` |  | 0 |  |
| `GETMAIN svc_bare` |  | 0 |  |
| `FREEMAIN svc_bare` |  | 0 |  |
| `LEDON board` |  | 0 |  |
| `BUTTON board` |  | 0 |  |
| `STR data` |  | 0 |  |
| `WORDS data` |  | 0 |  |
| `BYTES data` |  | 0 |  |
| `SPACE data` |  | 0 |  |
| `CHECKINIT check` |  | 0 |  |
| `CHECK check` |  | 0 |  |
| `CHECKEND check` |  | 0 |  |
| `REQUIRE check` |  | 0 |  |
| `DIV rt` |  | 0 |  |
| `MOD rt` |  | 0 |  |
| `RTCALL rt` |  | 0 |  |
| `DSECT struct` |  | 0 |  |
| `USECT struct` |  | 0 |  |
| `FIELD struct` |  | 0 |  |
| `DEND struct` |  | 0 |  |

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

### Batch 2: control flow (step 13)

### demo: calls, recursion, loops, bit operations

[`demo.c`](../../sw-cor24-x-tinyc/demos/demo.c) (51 lines; 245 lines of tc24r assembly) →
[`demos/tinyc/demo.hlasm`](../demos/tinyc/demo.hlasm) (93 lines).
Macros: `CALL`, `PROLOG`/`ARG`/`LOCAL`/`RETURN`, `DO`/`DOEXIT`, `IF`/`ELSE`, `CHECK`, `WORDS`.

<details><summary>C source</summary>

```c
int counter = 0;

int add(int a, int b) {
    return a + b;
}

int fib(int n) {
    if (n < 2) { return 1; }
    return fib(n - 1) + fib(n - 2);
}

int bitops(int x) {
    int a = x & 15;
    int b = a | 32;
    int c = b ^ 7;
    int d = c << 1;
    int e = d >> 1;
    return e;
}

int main() {
    int small = 42;
    int large = 1000;

    int sum = add(17, 25);

    if (sum == small) {
        counter = 1;
    } else {
        counter = 0;
    }

    int total = 0;
    int i = 1;
    while (i <= 5) {
        total = total + i;
        i = i + 1;
    }

    for (int j = 6; j <= 10; j = j + 1) {
        total = total + j;
    }

    int f = fib(6);

    int b = bitops(large);

    int neg = -1;
    int bitnot = ~0;
    int lognot = !0;

    int ok = 1;
    if (sum != 42) { ok = 0; }
    if (total != 55) { ok = 0; }
    if (f != 13) { ok = 0; }
    if (counter != 1) { ok = 0; }
    if (neg != -1) { ok = 0; }
    if (lognot != 1) { ok = 0; }

    if (ok == 1) {
        return 42;
    }
    return 0;
}
```

</details>

```
; demo.c in hlasm: calls, recursion (fib), while and for loops, bit
; operations; returns 42 when every check holds (no UART output in the C).
; Output: "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY data
COPY check
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
; sum = add(17, 25); counter = (sum == small)
 CALL _add,17,25
 mov r2,r0
 la r1,_counter
IF cc_eq,r2,42
 lc r0,1
ELSE
 lc r0,0
ENDIF
 sw r0,0(r1)
 CHECK cc_eq,r2,42
; total = 1 + ... + 5 (while), then + 6 + ... + 10 (for)
 lc r0,0
 lc r2,1
DO
 DOEXIT cc_gt,r2,5
 add r0,r2
 add r2,1
ENDDO
 lc r2,6
DO
 DOEXIT cc_gt,r2,10
 add r0,r2
 add r2,1
ENDDO
 CHECK cc_eq,r0,55
; f = fib(6)
 CALL _fib,6
 CHECK cc_eq,r0,13
; b = bitops(large) (computed, not checked, as in the C)
 CALL _bitops,1000
; counter == 1; neg == -1; !0 == 1
 la r1,_counter
 lw r0,0(r1)
 CHECK cc_eq,r0,1
 lc r0,-1
 CHECK cc_eq,r0,-1
 lc r0,1
 CHECK cc_eq,r0,1
 CHECKEND ,42
 RET
 WORDS _counter,0

; _add(a, b) = a + b
_add:
 PROLOG
 ARG r0,1
 ARG r1,2
 add r0,r1
 RET

; _fib(n) = 1 if n < 2, else fib(n-1) + fib(n-2)
_fib:
 LOCAL F1,3
 PROLOG
 ARG r2,1
IF cc_lt,r2,2
 RETURN 1
ENDIF
 add r2,-1
 CALL _fib,r2
 sw r0,F1(fp)
 add r2,-1
 CALL _fib,r2
 lw r1,F1(fp)
 add r0,r1
 RET

; _bitops(x) = (((x & 15) | 32) ^ 7) << 1 >> 1
_bitops:
 PROLOG
 ARG r0,1
 lc r1,15
 and r0,r1
 lc r1,32
 or r0,r1
 lc r1,7
 xor r0,r1
 lc r1,1
 shl r0,r1
 sra r0,r1
 RET
COPY svc_bare_code
```

Output:

```
r0=42
```

### demo4: software divide and modulo

[`demo4.c`](../../sw-cor24-x-tinyc/demos/demo4.c) (37 lines; 236 lines of tc24r assembly) →
[`demos/tinyc/demo4.hlasm`](../demos/tinyc/demo4.hlasm) (30 lines).
Macros: `DIV`, `MOD`, a demo-local test macro `T`, `CHECK`.

<details><summary>C source</summary>

```c
// tc24r demo4 -- software divide and modulo
//
// New features:
//   - Integer division (/) via software __tc24r_div
//   - Integer modulo (%) via software __tc24r_mod
//
// Expected: r0 = 42, UART output: "D4OK"

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
    int ok = 1;

    // basic division
    if (17 / 5 != 3) { ok = 0; }
    if (17 % 5 != 2) { ok = 0; }

    // exact division
    if (100 / 10 != 10) { ok = 0; }
    if (100 % 10 != 0) { ok = 0; }

    // divide by 1
    if (42 / 1 != 42) { ok = 0; }
    if (42 % 1 != 0) { ok = 0; }

    // dividend < divisor
    if (3 / 7 != 0) { ok = 0; }
    if (3 % 7 != 3) { ok = 0; }

    if (ok == 1) {
        puts("D4OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo4.c in hlasm: software divide and modulo (COR24 has no divide
; instruction; DIV and MOD call the library's routines). Prints "D4OK" and
; returns 42. Output: "D4OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
COPY rt
SET SHOWRC,1

; T op,a,b,expected: one check of a op b
MACRO T &OP,&A,&B,&E
 &OP &A,&B
 CHECK cc_eq,r0,&E
MEND

 START
_main:
 PROLOG
 CHECKINIT
 T DIV,17,5,3
 T MOD,17,5,2
 T DIV,100,10,10
 T MOD,100,10,0
 T DIV,42,1,42
 T MOD,42,1,0
 T DIV,3,7,0
 T MOD,3,7,3
 CHECKEND "D4OK\n",42
 RET
COPY svc_bare_code
COPY rt_code
```

Output:

```
D4OK
r0=42
```

### demo11: && and || with short-circuit

[`demo11.c`](../../sw-cor24-x-tinyc/demos/demo11.c) (34 lines; 206 lines of tc24r assembly) →
[`demos/tinyc/demo11.hlasm`](../demos/tinyc/demo11.hlasm) (52 lines).
Macros: demo-local `AND2`/`OR2` built from nested `IF` (hlasm has no `AND`/`OR` yet), `LOADR`, `CHECK`.

<details><summary>C source</summary>

```c
// tc24r demo11 -- logical AND (&&) and OR (||) with short-circuit
//
// New features:
//   - && operator with short-circuit (0 && x skips x, yields 0)
//   - || operator with short-circuit (1 || x skips x, yields 1)
//   - Correct C precedence: || below &&, && below bitwise |
//
// Expected: r0 = 42, UART output: "D11OK"

#define UART_DATA   0xFF0100
#define UART_STATUS 0xFF0101

void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }

void puts(char *s) {
    while (*s) { putc(*s); s = s + 1; }
}

int main() {
    int ok = 1;

    // && both true
    if (!(1 && 2)) { ok = 0; }

    // && short-circuit: first false
    if (0 && 1) { ok = 0; }

    // || first true
    if (!(1 || 0)) { ok = 0; }

    // || both false
    if (0 || 0) { ok = 0; }

    // || second true
    if (!(0 || 5)) { ok = 0; }

    // mixed: (1 && 0) || 1 = 1
    if (!((1 && 0) || 1)) { ok = 0; }

    if (ok) {
        puts("D11OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo11.c in hlasm: && and || with short-circuit evaluation. hlasm has no
; compound conditions yet, so two demo-local macros build them from nested
; IFs, setting r2 to 0 or 1 and evaluating b only when it matters.
; Prints "D11OK" and returns 42. Output: "D11OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1

; AND2 a,b: r2 = (a && b); OR2 a,b: r2 = (a || b). a and b are registers
; (other than r2 for b) or constants.
MACRO AND2 &A,&B
 LOADR r0,&A
 lc r2,0
IF cc_ne,r0,0
 LOADR r0,&B
IF cc_ne,r0,0
 lc r2,1
ENDIF
ENDIF
MEND

MACRO OR2 &A,&B
 LOADR r0,&A
 lc r2,1
IF cc_eq,r0,0
 LOADR r0,&B
IF cc_eq,r0,0
 lc r2,0
ENDIF
ENDIF
MEND

 START
_main:
 PROLOG
 CHECKINIT
 AND2 1,2
 CHECK cc_eq,r2,1
 AND2 0,1
 CHECK cc_eq,r2,0
 OR2 1,0
 CHECK cc_eq,r2,1
 OR2 0,0
 CHECK cc_eq,r2,0
 OR2 0,5
 CHECK cc_eq,r2,1
; (1 && 0) || 1
 AND2 1,0
 OR2 r2,1
 CHECK cc_eq,r2,1
 CHECKEND "D11OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
D11OK
r0=42
```

### demo12: do...while

[`demo12.c`](../../sw-cor24-x-tinyc/demos/demo12.c) (36 lines; 148 lines of tc24r assembly) →
[`demos/tinyc/demo12.hlasm`](../demos/tinyc/demo12.hlasm) (36 lines).
Macros: `DO` with the exit test last, `DOEXIT` alone (C's `while (0)`), `cc_ge`, `cc_le`.

<details><summary>C source</summary>

```c
// tc24r demo12 -- do...while loop
//
// New feature:
//   - do { body } while (cond); -- executes body at least once
//
// Expected: r0 = 42, UART output: "D12OK"

#define UART_DATA   0xFF0100
#define UART_STATUS 0xFF0101

void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

int main() {
    int ok = 1;

    // do...while executes at least once even if cond is false
    int ran = 0;
    do {
        ran = 1;
    } while (0);
    if (!ran) { ok = 0; }

    // do...while loop counting
    int i = 0;
    do {
        i = i + 1;
    } while (i < 5);
    if (i != 5) { ok = 0; }

    // compared with while (would not execute)
    int j = 0;
    while (j > 100) {
        j = 999;
    }
    if (j != 0) { ok = 0; }

    if (ok) {
        puts("D12OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo12.c in hlasm: do...while runs its body at least once (DO with the
; exit test at the end); a while loop whose condition is false never runs.
; Prints "D12OK" and returns 42. Output: "D12OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
; do { ran = 1; } while (0);
 lc r2,0
DO
 lc r2,1
 DOEXIT
ENDDO
 CHECK cc_eq,r2,1
; do { i = i + 1; } while (i < 5);
 lc r2,0
DO
 add r2,1
 DOEXIT cc_ge,r2,5
ENDDO
 CHECK cc_eq,r2,5
; while (j > 100) { j = 999; }
 lc r2,0
DO
 DOEXIT cc_le,r2,100
 la r2,999
ENDDO
 CHECK cc_eq,r2,0
 CHECKEND "D12OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
D12OK
r0=42
```

### demo13: break and continue

[`demo13.c`](../../sw-cor24-x-tinyc/demos/demo13.c) (49 lines; 241 lines of tc24r assembly) →
[`demos/tinyc/demo13.hlasm`](../demos/tinyc/demo13.hlasm) (72 lines).
Macros: `DOEXIT` (break), `ITERATE` (continue), `MOD`, `LOCAL`.

<details><summary>C source</summary>

```c
// tc24r demo13 -- break and continue
//
// New features:
//   - break: exits innermost loop
//   - continue: jumps to loop increment/condition
//   - Works in while, do...while, and for loops
//
// Expected: r0 = 42, UART output: "D13OK"

#define UART_DATA   0xFF0100
#define UART_STATUS 0xFF0101
void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

int main() {
    int ok = 1;

    // break in while
    int i = 0;
    while (1) {
        if (i == 5) { break; }
        i = i + 1;
    }
    if (i != 5) { ok = 0; }

    // continue in while (sum odd numbers 1-9)
    int sum = 0;
    int j = 0;
    while (j < 10) {
        j = j + 1;
        if (j % 2 == 0) { continue; }
        sum = sum + j;
    }
    if (sum != 25) { ok = 0; }

    // break in for
    int k = 0;
    for (k = 0; k < 100; k = k + 1) {
        if (k == 3) { break; }
    }
    if (k != 3) { ok = 0; }

    // continue in for (skip evens)
    int total = 0;
    for (int n = 1; n <= 5; n = n + 1) {
        if (n % 2 == 0) { continue; }
        total = total + n;
    }
    if (total != 9) { ok = 0; }

    if (ok) {
        puts("D13OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo13.c in hlasm: break is DOEXIT, continue is ITERATE, in while and for
; loops. In a for loop the increment must still run on continue, so it goes
; at the top of the loop. Prints "D13OK" and returns 42.
; Output: "D13OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
COPY rt
SET SHOWRC,1
 START
_main:
 LOCAL SUM,3
 PROLOG
 CHECKINIT
; while (1) { if (i == 5) break; i = i + 1; }
 lc r2,0
DO
IF cc_eq,r2,5
 DOEXIT
ENDIF
 add r2,1
ENDDO
 CHECK cc_eq,r2,5
; while (j < 10) { j = j + 1; if (j % 2 == 0) continue; sum = sum + j; }
 lc r0,0
 sw r0,SUM(fp)
 lc r2,0
DO
 DOEXIT cc_ge,r2,10
 add r2,1
 MOD r2,2
IF cc_eq,r0,0
 ITERATE
ENDIF
 lw r0,SUM(fp)
 add r0,r2
 sw r0,SUM(fp)
ENDDO
 lw r0,SUM(fp)
 CHECK cc_eq,r0,25
; for (k = 0; k < 100; k = k + 1) { if (k == 3) break; }
 lc r2,0
DO
 DOEXIT cc_ge,r2,100
IF cc_eq,r2,3
 DOEXIT
ENDIF
 add r2,1
ENDDO
 CHECK cc_eq,r2,3
; for (n = 1; n <= 5; n = n + 1) { if (n % 2 == 0) continue; total += n; }
 lc r0,0
 sw r0,SUM(fp)
 lc r2,0
DO
 add r2,1
 DOEXIT cc_gt,r2,5
 MOD r2,2
IF cc_eq,r0,0
 ITERATE
ENDIF
 lw r0,SUM(fp)
 add r0,r2
 sw r0,SUM(fp)
ENDDO
 lw r0,SUM(fp)
 CHECK cc_eq,r0,9
 CHECKEND "D13OK\n",42
 RET
COPY svc_bare_code
COPY rt_code
```

Output:

```
D13OK
r0=42
```

### demo14: increment and decrement

[`demo14.c`](../../sw-cor24-x-tinyc/demos/demo14.c) (38 lines; 208 lines of tc24r assembly) →
[`demos/tinyc/demo14.hlasm`](../demos/tinyc/demo14.hlasm) (40 lines).
Macros: plain `add`, `DO`, `CHECK`.

<details><summary>C source</summary>

```c
// tc24r demo14 -- increment and decrement operators
//
// New features:
//   - Prefix: ++i, --i (returns new value)
//   - Postfix: i++, i-- (returns old value)
//
// Expected: r0 = 42, UART output: "D14OK"

#define UART_DATA   0xFF0100
#define UART_STATUS 0xFF0101
void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

int main() {
    int ok = 1;

    // basic increment
    int a = 5;
    a++;
    if (a != 6) { ok = 0; }

    // basic decrement
    a--;
    if (a != 5) { ok = 0; }

    // postfix returns old value
    int b = a++;
    if (b != 5 || a != 6) { ok = 0; }

    // prefix returns new value
    int c = ++a;
    if (c != 7 || a != 7) { ok = 0; }

    // in for loop
    int sum = 0;
    for (int i = 0; i < 5; i++) {
        sum = sum + i;
    }
    if (sum != 10) { ok = 0; }

    if (ok) {
        puts("D14OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo14.c in hlasm: ++ and -- are add 1 / add -1; postfix keeps the old
; value, prefix uses the new one. Prints "D14OK" and returns 42.
; Output: "D14OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
; int a = 5; a++; a--;
 lc r2,5
 add r2,1
 CHECK cc_eq,r2,6
 add r2,-1
 CHECK cc_eq,r2,5
; int b = a++;
 mov r0,r2
 add r2,1
 CHECK cc_eq,r0,5
 CHECK cc_eq,r2,6
; int c = ++a;
 add r2,1
 mov r0,r2
 CHECK cc_eq,r0,7
 CHECK cc_eq,r2,7
; for (i = 0; i < 5; i++) sum = sum + i;
 lc r0,0
 lc r2,0
DO
 DOEXIT cc_ge,r2,5
 add r0,r2
 add r2,1
ENDDO
 CHECK cc_eq,r0,10
 CHECKEND "D14OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
D14OK
r0=42
```

### demo15: the ternary operator

[`demo15.c`](../../sw-cor24-x-tinyc/demos/demo15.c) (37 lines; 244 lines of tc24r assembly) →
[`demos/tinyc/demo15.hlasm`](../demos/tinyc/demo15.hlasm) (65 lines).
Macros: `IF`/`ELSEIF`/`ELSE`, `cc_gt`, `cc_le`, `CALL`.

<details><summary>C source</summary>

```c
// tc24r demo15 -- ternary operator (? :)
//
// New feature:
//   - Conditional expression: cond ? then_expr : else_expr
//   - Right-associative, nestable
//   - Correct C precedence (between assignment and logical-or)
//
// Expected: r0 = 42, UART output: "D15OK"

#define UART_DATA 0xFF0100
#define UART_STATUS 0xFF0101
void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

int abs(int x) {
    return x >= 0 ? x : -x;
}

int max(int a, int b) {
    return a > b ? a : b;
}

int main() {
    int ok = 1;

    // basic true/false
    if ((1 ? 42 : 0) != 42) { ok = 0; }
    if ((0 ? 42 : 99) != 99) { ok = 0; }

    // nested ternary
    int x = 3;
    int r = x > 5 ? 1 : x > 2 ? 2 : 3;
    if (r != 2) { ok = 0; }

    // in function
    if (abs(-7) != 7) { ok = 0; }
    if (abs(3) != 3) { ok = 0; }
    if (max(10, 20) != 20) { ok = 0; }

    if (ok) {
        puts("D15OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo15.c in hlasm: the ternary operator is IF/ELSE (a nested ternary is
; ELSEIF); abs and max are routines. Prints "D15OK" and returns 42.
; Output: "D15OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
; (1 ? 42 : 0) and (0 ? 42 : 99)
 lc r2,1
IF cc_ne,r2,0
 lc r0,42
ELSE
 lc r0,0
ENDIF
 CHECK cc_eq,r0,42
 lc r2,0
IF cc_ne,r2,0
 lc r0,42
ELSE
 lc r0,99
ENDIF
 CHECK cc_eq,r0,99
; r = x > 5 ? 1 : x > 2 ? 2 : 3;  with x = 3
 lc r2,3
IF cc_gt,r2,5
 lc r0,1
ELSEIF cc_gt,r2,2
 lc r0,2
ELSE
 lc r0,3
ENDIF
 CHECK cc_eq,r0,2
 CALL _abs,-7
 CHECK cc_eq,r0,7
 CALL _abs,3
 CHECK cc_eq,r0,3
 CALL _max,10,20
 CHECK cc_eq,r0,20
 CHECKEND "D15OK\n",42
 RET

; _abs(x) = x >= 0 ? x : -x
_abs:
 PROLOG
 ARG r0,1
IF cc_lt,r0,0
 lc r1,0
 sub r1,r0
 mov r0,r1
ENDIF
 RET

; _max(a, b) = a > b ? a : b
_max:
 PROLOG
 ARG r0,1
 ARG r1,2
IF cc_le,r0,r1
 mov r0,r1
ENDIF
 RET
COPY svc_bare_code
```

Output:

```
D15OK
r0=42
```

### demo21: compound assignment

[`demo21.c`](../../sw-cor24-x-tinyc/demos/demo21.c) (42 lines; 255 lines of tc24r assembly) →
[`demos/tinyc/demo21.hlasm`](../demos/tinyc/demo21.hlasm) (51 lines).
Macros: one instruction per operator, `DIV`/`MOD`.

<details><summary>C source</summary>

```c
// tc24r demo21 -- compound assignment operators
//
// New features:
//   +=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>=
//   Desugared at parse time: x += e becomes x = x + e
//
// Expected: r0 = 42, UART output: "D21OK"

#define UART_DATA 0xFF0100
#define UART_STATUS 0xFF0101
void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

int main() {
    int ok = 1;

    int a = 10;
    a += 5;
    if (a != 15) { ok = 0; }

    a -= 3;
    if (a != 12) { ok = 0; }

    a *= 2;
    if (a != 24) { ok = 0; }

    a /= 4;
    if (a != 6) { ok = 0; }

    a %= 4;
    if (a != 2) { ok = 0; }

    int b = 0xFF;
    b &= 0x0F;
    if (b != 15) { ok = 0; }

    b |= 0x30;
    if (b != 63) { ok = 0; }

    b ^= 0xFF;
    if (b != 192) { ok = 0; }

    int c = 1;
    c <<= 3;
    if (c != 8) { ok = 0; }

    c >>= 1;
    if (c != 4) { ok = 0; }

    if (ok) {
        puts("D21OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo21.c in hlasm: each compound assignment is one instruction (or a DIV
; or MOD call) on the register holding the variable. Prints "D21OK" and
; returns 42. Output: "D21OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
COPY rt
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
; a = 10; a += 5; a -= 3; a *= 2; a /= 4; a %= 4;
 lc r2,10
 add r2,5
 CHECK cc_eq,r2,15
 add r2,-3
 CHECK cc_eq,r2,12
 lc r1,2
 mul r2,r1
 CHECK cc_eq,r2,24
 DIV r2,4
 mov r2,r0
 CHECK cc_eq,r2,6
 MOD r2,4
 mov r2,r0
 CHECK cc_eq,r2,2
; b = 0xFF; b &= 0x0F; b |= 0x30; b ^= 0xFF;
 la r2,0xFF
 lc r1,0x0F
 and r2,r1
 CHECK cc_eq,r2,15
 lc r1,0x30
 or r2,r1
 CHECK cc_eq,r2,63
 la r1,0xFF
 xor r2,r1
 CHECK cc_eq,r2,192
; c = 1; c <<= 3; c >>= 1;
 lc r2,1
 lc r1,3
 shl r2,r1
 CHECK cc_eq,r2,8
 lc r1,1
 sra r2,r1
 CHECK cc_eq,r2,4
 CHECKEND "D21OK\n",42
 RET
COPY svc_bare_code
COPY rt_code
```

Output:

```
D21OK
r0=42
```

### demo26: switch/case

[`demo26.c`](../../sw-cor24-x-tinyc/demos/demo26.c) (84 lines; 420 lines of tc24r assembly) →
[`demos/tinyc/demo26.hlasm`](../demos/tinyc/demo26.hlasm) (87 lines).
Macros: `SELECT`/`WHEN`/`OTHERWISE`, `RETURN` inside `WHEN`, range tests for fall-through.

<details><summary>C source</summary>

```c
// tc24r demo26 -- switch/case
//
// New features:
//   - switch (expr) { case V: ... break; default: ... }
//   - fall-through between cases
//   - break exits switch (not enclosing loop)
//
// Expected: r0 = 42, UART output: "D26OK"

#define UART_DATA 0xFF0100
#define UART_STATUS 0xFF0101
void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

int classify(int x) {
    switch (x) {
        case 0:
            return 10;
        case 1:
            return 20;
        case 2:
            return 30;
        default:
            return 99;
    }
}

int main() {
    int ok = 1;

    // basic case matching
    if (classify(0) != 10) ok = 0;
    if (classify(1) != 20) ok = 0;
    if (classify(2) != 30) ok = 0;
    if (classify(3) != 99) ok = 0;

    // switch with break (no fall-through)
    int result = 0;
    int val = 2;
    switch (val) {
        case 1:
            result = 11;
            break;
        case 2:
            result = 22;
            break;
        case 3:
            result = 33;
            break;
    }
    if (result != 22) ok = 0;

    // fall-through behavior
    int count = 0;
    switch (1) {
        case 1:
            count = count + 1;
        case 2:
            count = count + 1;
        case 3:
            count = count + 1;
            break;
        default:
            count = 100;
    }
    if (count != 3) ok = 0;

    // switch inside a loop -- break targets switch, not loop
    int sum = 0;
    int i = 0;
    while (i < 4) {
        switch (i) {
            case 0:
                sum = sum + 1;
                break;
            case 1:
                sum = sum + 10;
                break;
            default:
                sum = sum + 100;
                break;
        }
        i = i + 1;
    }
    if (sum != 211) ok = 0;

    if (ok) {
        puts("D26OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo26.c in hlasm: switch is SELECT/WHEN/OTHERWISE. A WHEN arm never
; falls into the next one, so the C fall-through case is written as the
; range tests it amounts to. Prints "D26OK" and returns 42.
; Output: "D26OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
 CALL _classify,0
 CHECK cc_eq,r0,10
 CALL _classify,1
 CHECK cc_eq,r0,20
 CALL _classify,2
 CHECK cc_eq,r0,30
 CALL _classify,3
 CHECK cc_eq,r0,99
; switch (val) with breaks, val = 2
 lc r0,0
 lc r2,2
SELECT r2
WHEN 1
 lc r0,11
WHEN 2
 lc r0,22
WHEN 3
 lc r0,33
ENDSEL
 CHECK cc_eq,r0,22
; switch (1) where cases 1 and 2 fall through to 3: entering at case k
; runs every case from k to 3; any other value runs the default
 lc r0,0
 lc r2,1
IF cc_ge,r2,1
IF cc_le,r2,3
IF cc_le,r2,1
 add r0,1
ENDIF
IF cc_le,r2,2
 add r0,1
ENDIF
 add r0,1
ELSE
 lc r0,100
ENDIF
ELSE
 lc r0,100
ENDIF
 CHECK cc_eq,r0,3
; a switch inside a loop
 lc r0,0
 lc r2,0
DO
 DOEXIT cc_ge,r2,4
SELECT r2
WHEN 0
 add r0,1
WHEN 1
 add r0,10
OTHERWISE
 add r0,100
ENDSEL
 add r2,1
ENDDO
 la r1,211
 CHECK cc_eq,r0,r1
 CHECKEND "D26OK\n",42
 RET

; _classify(x): 0 -> 10, 1 -> 20, 2 -> 30, otherwise 99
_classify:
 PROLOG
 ARG r0,1
SELECT r0
WHEN 0
 RETURN 10
WHEN 1
 RETURN 20
WHEN 2
 RETURN 30
OTHERWISE
 RETURN 99
ENDSEL
COPY svc_bare_code
```

Output:

```
D26OK
r0=42
```

### demo46: signed and unsigned comparisons and shifts

[`demo46.c`](../../sw-cor24-x-tinyc/demos/demo46.c) (60 lines; 262 lines of tc24r assembly) →
[`demos/tinyc/demo46.hlasm`](../demos/tinyc/demo46.hlasm) (44 lines).
Macros: `sra`/`srl`, `cc_lt`/`cc_le`, `cc_lu`/`cc_gtu`/`cc_geu`.

<details><summary>C source</summary>

```c
// tc24r demo46 -- unsigned int, signed/unsigned shifts and comparisons
//
// Tests:
//   1. unsigned int declaration and arithmetic
//   2. Arithmetic right shift (>>) on signed int (sign-extends)
//   3. Logical right shift (>>) on unsigned int (zero-fills)
//   4. Signed comparison (< > <= >=) on negative values
//   5. Unsigned comparison (< > <= >=) treats all values as positive
//   6. Mixed signed/unsigned in expressions

void putc_uart(int ch) {
    while (*(char *)0xFF0101 & 0x80) {}
    *(char *)0xFF0100 = ch;
}

int ok;

void check(int cond, int id) {
    if (!cond) {
        ok = 0;
        putc_uart(70);   // 'F'
        putc_uart(48 + id);
    }
}

int main() {
    ok = 1;

    // --- signed right shift (arithmetic: sign-extends) ---
    int s = -84;
    int shr_s = s >> 2;
    check(shr_s == -21, 1);       // -84 >> 2 = -21 (arithmetic)

    // --- unsigned right shift (logical: zero-fills) ---
    unsigned int u = 0x7FFFAC;    // large positive (fits 24-bit unsigned)
    unsigned int shr_u = u >> 4;
    check(shr_u == 0x07FFFA, 2);  // logical shift, no sign extension

    // --- unsigned wrapping: 0 - 1 wraps to max ---
    unsigned int zero = 0;
    unsigned int wrapped = zero - 1;  // should be 0xFFFFFF (16777215)
    check(wrapped == 16777215, 3);

    // --- signed comparison: -1 < 0 ---
    int neg = -1;
    check(neg < 0, 4);
    check(neg <= 0, 5);

    // --- unsigned comparison: (unsigned)-1 > 0 ---
    // In unsigned, -1 cast is 0xFFFFFF which is > 0
    unsigned int big = 16777215;  // 0xFFFFFF
    check(big > 0, 6);
    check(big >= 1, 7);

    // --- unsigned < : 5 < 10 ---
    unsigned int a = 5;
    unsigned int b = 10;
    check(a < b, 8);
    check(b > a, 9);

    if (ok == 1) {
        putc_uart(68);  // 'D'
        putc_uart(52);  // '4'
        putc_uart(54);  // '6'
        putc_uart(79);  // 'O'
        putc_uart(75);  // 'K'
        putc_uart(10);
        return 42;
    }
    return 0;
}
```

</details>

```
; demo46.c in hlasm: signed and unsigned values. sra and srl are the
; arithmetic and logical right shifts; cc_lt/cc_le compare signed and
; cc_lu/cc_gtu/cc_geu unsigned. Prints "D46OK" and returns 42.
; Output: "D46OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
; -84 >> 2 == -21 (arithmetic shift)
 lc r2,-84
 lc r1,2
 sra r2,r1
 CHECK cc_eq,r2,-21
; 0x7FFFAC >> 4 == 0x07FFFA (logical shift)
 la r2,0x7FFFAC
 lc r1,4
 srl r2,r1
 CHECK cc_eq,r2,0x07FFFA
; unsigned 0 - 1 == 0xFFFFFF
 lc r2,0
 add r2,-1
 CHECK cc_eq,r2,16777215
; signed: -1 < 0, -1 <= 0
 lc r2,-1
 CHECK cc_lt,r2,0
 CHECK cc_le,r2,0
; unsigned: 0xFFFFFF > 0, >= 1
 la r2,16777215
 CHECK cc_gtu,r2,0
 CHECK cc_geu,r2,1
; unsigned 5 < 10, 10 > 5
 lc r2,5
 lc r0,10
 CHECK cc_lu,r2,r0
 lc r0,10
 CHECK cc_gtu,r0,r2
 CHECKEND "D46OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
D46OK
r0=42
```

### demo11 again, with AND and OR (step 14)

After batch 2, hlasm gained compound conditions, so demo11 has a second port that uses them. [`demos/tinyc/demo11_andor.hlasm`](../demos/tinyc/demo11_andor.hlasm) (46 lines) replaces the nested-IF macros `AND2`/`OR2` of [demo11.hlasm](../demos/tinyc/demo11.hlasm) (52 lines) with `IF a,AND,b` and `IF a,OR,b`. The lowering is the same short-circuit branch sequence tc24r produces for `&&` and `||`, without first materialising 0 or 1.

```
; demo11.c in hlasm, second version: the && and || tests written with
; compound conditions (IF ...,AND,... / IF ...,OR,...), which lower to the
; same short-circuit branches as C. Compare demo11.hlasm, which builds them
; from nested IFs. Prints "D11OK" and returns 42.
; Output: "D11OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1

; FAILIF a,AND|OR,b: clear the ok flag when the two-term condition holds,
; as C's  if (a && b) { ok = 0; }  (each term is cc,register,value)
MACRO FAILIF &C1,&L1,&R1,&OP,&C2,&L2,&R2
IF &C1,&L1,&R1,&OP,&C2,&L2,&R2
 la r1,_chk_ok
 lc r0,0
 sw r0,0(r1)
ENDIF
MEND

 START
_main:
 PROLOG
 CHECKINIT
 lc r0,0
 lc r1,1
 lc r2,2
; if (!(1 && 2)) ok = 0;  -- fails unless both are non-zero
 FAILIF cc_eq,r1,0,OR,cc_eq,r2,0
; if (0 && 1) ok = 0;
 FAILIF cc_ne,r0,0,AND,cc_ne,r1,0
; if (!(1 || 0)) ok = 0;
 FAILIF cc_eq,r1,0,AND,cc_eq,r0,0
; if (0 || 0) ok = 0;
 FAILIF cc_ne,r0,0,OR,cc_ne,r0,0
; if (!(0 || 5)) ok = 0;  with 5 in r2
 lc r2,5
 FAILIF cc_eq,r0,0,AND,cc_eq,r2,0
; if (!((1 && 0) || 1)) ok = 0;  -- (1 && 0) is false, so this is !1
 lc r2,0
IF cc_ne,r1,0,AND,cc_ne,r2,0
 lc r2,1
ENDIF
 FAILIF cc_eq,r2,0,AND,cc_eq,r1,0
 CHECKEND "D11OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
D11OK
r0=42
```

### Batch 3: functions, arrays, pointers, strings (step 15)

Several of these demos report a failed check by returning a small error code (`if (x != 7) return 1;`); `REQUIRE cond,a,b,rc` is that pattern.

### demo5: local arrays and passing them

[`demo5.c`](../../sw-cor24-x-tinyc/demos/demo5.c) (52 lines; 275 lines of tc24r assembly) →
[`demos/tinyc/demo5.hlasm`](../demos/tinyc/demo5.hlasm) (64 lines).
Macros: `LOCAL` with `A+3(fp)` offsets, `LOCADDR`, `CALL`, `CHECK`.

<details><summary>C source</summary>

```c
// tc24r demo5 -- arrays
//
// New features:
//   - Array declarations: int a[N]
//   - Array indexing: a[i] (read and write)
//   - Array name decays to pointer to first element
//
// Expected: r0 = 42, UART output: "D5OK"

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

int sum_array(int *arr, int len) {
    int total = 0;
    int i = 0;
    while (i < len) {
        total = total + *(arr + i);
        i = i + 1;
    }
    return total;
}

int main() {
    int ok = 1;

    // basic array read/write
    int a[4];
    a[0] = 10;
    a[1] = 20;
    a[2] = 30;
    a[3] = 40;
    if (a[0] + a[3] != 50) { ok = 0; }

    // array passed to function as pointer
    int total = sum_array(a, 4);
    if (total != 100) { ok = 0; }

    // char array
    char buf[3];
    buf[0] = 65;  // 'A'
    buf[1] = 66;  // 'B'
    buf[2] = 0;
    if (buf[0] != 65) { ok = 0; }
    if (buf[1] != 66) { ok = 0; }

    if (ok == 1) {
        puts("D5OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo5.c in hlasm: a local int array (one word per element, a[i] at
; A+3*i), passing it to a routine as a pointer, and a local char array.
; Prints "D5OK" and returns 42. Output: "D5OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1
 START
_main:
 LOCAL A,12
 LOCAL BUF,3
 PROLOG
 CHECKINIT
; a[0..3] = 10, 20, 30, 40
 lc r0,10
 sw r0,A(fp)
 lc r0,20
 sw r0,A+3(fp)
 lc r0,30
 sw r0,A+6(fp)
 lc r0,40
 sw r0,A+9(fp)
; a[0] + a[3] == 50
 lw r0,A(fp)
 lw r1,A+9(fp)
 add r0,r1
 CHECK cc_eq,r0,50
; sum_array(a, 4) == 100
 LOCADDR r2,A
 CALL _sum_array,r2,4
 CHECK cc_eq,r0,100
; char buf[3] = 'A', 'B', 0
 lc r0,65
 sb r0,BUF(fp)
 lc r0,66
 sb r0,BUF+1(fp)
 lc r0,0
 sb r0,BUF+2(fp)
 lbu r0,BUF(fp)
 CHECK cc_eq,r0,65
 lbu r0,BUF+1(fp)
 CHECK cc_eq,r0,66
 CHECKEND "D5OK\n",42
 RET

; _sum_array(arr, len): the sum of len words at arr
_sum_array:
 LOCAL SA_N,3
 PROLOG
 ARG r2,1
 ARG r0,2
 sw r0,SA_N(fp)
 lc r0,0
DO
 lw r1,SA_N(fp)
 DOEXIT cc_le,r1,0
 add r1,-1
 sw r1,SA_N(fp)
 lw r1,0(r2)
 add r0,r1
 add r2,3
ENDDO
 RET
COPY svc_bare_code
```

Output:

```
D5OK
r0=42
```

### demo6: global char, int and pointer

[`demo6.c`](../../sw-cor24-x-tinyc/demos/demo6.c) (44 lines; 154 lines of tc24r assembly) →
[`demos/tinyc/demo6.hlasm`](../demos/tinyc/demo6.hlasm) (45 lines).
Macros: `BYTES`, `WORDS`, `CHECK`.

<details><summary>C source</summary>

```c
// tc24r demo6 -- global char, global pointer, global array-like patterns
//
// New features / fixes:
//   - Global char variables use .byte (not .word)
//   - Global char load/store uses lbu/sb
//   - Global pointer declarations (int *ptr)
//   - Global pointer lookahead fix (int *ptr vs int func())
//
// Expected: r0 = 42, UART output: "D6OK"

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

char flag = 0;
int counter = 0;
int *cptr;

int main() {
    int ok = 1;

    // global char: read initial value
    if (flag != 0) { ok = 0; }

    // global char: write and read back
    flag = 1;
    if (flag != 1) { ok = 0; }

    // global int: write and read back
    counter = 100;
    if (counter != 100) { ok = 0; }

    // global pointer: point to global int
    cptr = &counter;
    *cptr = 200;
    if (counter != 200) { ok = 0; }

    // global pointer: read through pointer
    if (*cptr != 200) { ok = 0; }

    if (ok == 1) {
        puts("D6OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo6.c in hlasm: global char, int and pointer variables (labelled data
; after the code), written directly and through the pointer.
; Prints "D6OK" and returns 42. Output: "D6OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY data
COPY check
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
; flag == 0, then flag = 1
 la r2,_flag
 lbu r0,0(r2)
 CHECK cc_eq,r0,0
 lc r0,1
 sb r0,0(r2)
 lbu r0,0(r2)
 CHECK cc_eq,r0,1
; counter = 100
 la r2,_counter
 la r0,100
 sw r0,0(r2)
 lw r0,0(r2)
 CHECK cc_eq,r0,100
; cptr = &counter; *cptr = 200
 la r1,_cptr
 la r0,_counter
 sw r0,0(r1)
 lw r2,0(r1)
 la r0,200
 sw r0,0(r2)
 la r1,_counter
 lw r0,0(r1)
 CHECK cc_eq,r0,200
 lw r0,0(r2)
 CHECK cc_eq,r0,200
 CHECKEND "D6OK\n",42
 RET
 BYTES _flag,0
 WORDS _counter,0
 WORDS _cptr,0
COPY svc_bare_code
```

Output:

```
D6OK
r0=42
```

### demo7: pointer arithmetic and difference

[`demo7.c`](../../sw-cor24-x-tinyc/demos/demo7.c) (52 lines; 274 lines of tc24r assembly) →
[`demos/tinyc/demo7.hlasm`](../demos/tinyc/demo7.hlasm) (49 lines).
Macros: `LOCADDR`, `DIV`, `RTCALL strlen`, `STR`.

<details><summary>C source</summary>

```c
// tc24r demo7 -- pointer subtraction
//
// New features:
//   - ptr - int: retreats pointer by n elements (scaled)
//   - ptr - ptr: yields element count between two pointers
//
// Expected: r0 = 42, UART output: "D7OK"

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
    char *p = s;
    while (*p) {
        p = p + 1;
    }
    return p - s;
}

int main() {
    int ok = 1;

    // ptr - int: retreat through int array
    int a[3];
    a[0] = 10;
    a[1] = 20;
    a[2] = 30;
    int *p = a + 2;
    p = p - 1;
    if (*p != 20) { ok = 0; }

    // ptr - ptr on int pointers
    int *start = a;
    int *end = a + 3;
    if (end - start != 3) { ok = 0; }

    // ptr - ptr on char pointers (strlen)
    int len = strlen("Hello");
    if (len != 5) { ok = 0; }

    // char ptr - int
    char *s = "ABCDE";
    char *mid = s + 4;
    mid = mid - 2;
    if (*mid != 67) { ok = 0; }  /* 'C' = 67 */

    if (ok == 1) {
        puts("D7OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo7.c in hlasm: pointer arithmetic is byte arithmetic scaled by the
; element size (3 for int, 1 for char); pointer difference divides by it.
; Prints "D7OK" and returns 42. Output: "D7OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY data
COPY check
COPY rt
SET SHOWRC,1
 START
_main:
 LOCAL A,9
 PROLOG
 CHECKINIT
 lc r0,10
 sw r0,A(fp)
 lc r0,20
 sw r0,A+3(fp)
 lc r0,30
 sw r0,A+6(fp)
; int *p = a + 2; p = p - 1;  *p == 20
 LOCADDR r2,A
 add r2,6
 add r2,-3
 lw r0,0(r2)
 CHECK cc_eq,r0,20
; end - start == 3 (elements): 9 bytes / 3
 LOCADDR r2,A
 mov r0,r2
 add r0,9
 sub r0,r2
 DIV r0,3
 CHECK cc_eq,r0,3
; strlen("Hello") == 5
 RTCALL strlen,hello
 CHECK cc_eq,r0,5
; char *mid = s + 4; mid = mid - 2;  *mid == 'C'
 la r2,abcde
 add r2,4
 add r2,-2
 lbu r0,0(r2)
 CHECK cc_eq,r0,67
 CHECKEND "D7OK\n",42
 RET
 STR hello,"Hello"
 STR abcde,"ABCDE"
COPY svc_bare_code
COPY rt_code
```

Output:

```
D7OK
r0=42
```

### demo16: character literals

[`demo16.c`](../../sw-cor24-x-tinyc/demos/demo16.c) (30 lines; 150 lines of tc24r assembly) →
[`demos/tinyc/demo16.hlasm`](../demos/tinyc/demo16.hlasm) (31 lines).
Macros: `lc r0,'\n'` and other literals, `CHECK cc_le`.

<details><summary>C source</summary>

```c
// tc24r demo16 -- character literals
//
// New feature:
//   - 'a', '\n', '\0', '\\', '\'' character literals
//   - Evaluate to integer values (ASCII code)
//
// Expected: r0 = 42, UART output: "D16OK"

#define UART_DATA 0xFF0100
#define UART_STATUS 0xFF0101
void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

int main() {
    int ok = 1;

    if ('A' != 65) { ok = 0; }
    if ('0' != 48) { ok = 0; }
    if ('\n' != 10) { ok = 0; }
    if ('\0' != 0) { ok = 0; }
    if ('\\' != 92) { ok = 0; }
    if ('\'' != 39) { ok = 0; }

    // char literal in expression
    char c = 'Z';
    if (c != 90) { ok = 0; }

    // char literal comparison
    if ('a' > 'z') { ok = 0; }

    if (ok) {
        puts("D16OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo16.c in hlasm: character literals, including escapes, are numbers
; to hlasm. Prints "D16OK" and returns 42. Output: "D16OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
 lc r0,'A'
 CHECK cc_eq,r0,65
 lc r0,'0'
 CHECK cc_eq,r0,48
 lc r0,'\n'
 CHECK cc_eq,r0,10
 lc r0,'\0'
 CHECK cc_eq,r0,0
 lc r0,'\\'
 CHECK cc_eq,r0,92
 lc r0,'\''
 CHECK cc_eq,r0,39
 lc r0,'Z'
 CHECK cc_eq,r0,90
; 'a' > 'z' must be false
 lc r0,'a'
 CHECK cc_le,r0,'z'
 CHECKEND "D16OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
D16OK
r0=42
```

### demo39: printf

[`demo39.c`](../../sw-cor24-x-tinyc/demos/demo39.c) (26 lines; 1243 lines of tc24r assembly) →
[`demos/tinyc/demo39.hlasm`](../demos/tinyc/demo39.hlasm) (17 lines).
Macros: `WTO`, `PUTDEC`, `PUTC`, `PUTNL`.

<details><summary>C source</summary>

```c
// tc24r demo39 -- printf and long branches
//
// New features:
//   - #include <stdio.h> with freestanding printf
//   - printf("%d", val) with format specifiers
//   - Long branches (no 127-byte range limit)
//   - Varargs syntax (...) accepted in parameter lists
//
// Expected: r0 = 42, UART output: "D39OK"

#include <stdio.h>

int main() {
    int ok = 1;

    // printf with no args
    printf("D");

    // printf with %d
    printf("%d", 39);

    // printf with multiple args
    printf("%c%c", 79, 75);

    // newline
    printf("\n");

    // Verify the output was correct by checking we got here
    if (ok) {
        return 42;
    }
    return 0;
}
```

</details>

```
; demo39.c in hlasm: printf("D"), printf("%d", 39), printf("%c%c", 79, 75)
; and printf("\n") are WTO, PUTDEC and PUTC. Returns 42.
; Output: "D39OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
SET SHOWRC,1
 START
_main:
 PROLOG
 WTO "D"
 PUTDEC 39
 PUTC 79
 PUTC 75
 PUTNL
 RETURN 42
COPY svc_bare_code
```

Output:

```
D39OK
r0=42
```

### demo41: atoi and string.h

[`demo41.c`](../../sw-cor24-x-tinyc/demos/demo41.c) (34 lines; 2545 lines of tc24r assembly) →
[`demos/tinyc/demo41.hlasm`](../demos/tinyc/demo41.hlasm) (48 lines).
Macros: `RTCALL atoi/strlen/strcmp/strcpy`, `STR`, `LOCADDR`.

<details><summary>C source</summary>

```c
// tc24r demo41 -- getc, atoi, string.h functions
//
// New features:
//   - getchar()/getc() from UART RX
//   - atoi() string to integer
//   - strlen(), strcmp(), strcpy()
//
// Expected: r0 = 42, UART output: "D41OK"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    int ok = 1;

    // atoi
    if (atoi("42") != 42) ok = 0;
    if (atoi("-7") != -7) ok = 0;
    if (atoi("  100") != 100) ok = 0;

    // strlen
    if (strlen("hello") != 5) ok = 0;
    if (strlen("") != 0) ok = 0;

    // strcmp
    if (strcmp("abc", "abc") != 0) ok = 0;
    if (strcmp("abc", "abd") >= 0) ok = 0;
    if (strcmp("abd", "abc") <= 0) ok = 0;

    // strcpy
    char buf[8];
    strcpy(buf, "OK");
    if (strcmp(buf, "OK") != 0) ok = 0;

    if (ok) {
        printf("D41OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo41.c in hlasm: atoi, strlen, strcmp and strcpy from the runtime
; library (RTCALL), on string constants and a local buffer.
; Prints "D41OK" and returns 42. Output: "D41OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY data
COPY check
COPY rt
SET SHOWRC,1
 START
_main:
 LOCAL BUF,9
 PROLOG
 CHECKINIT
 RTCALL atoi,s42
 CHECK cc_eq,r0,42
 RTCALL atoi,sm7
 CHECK cc_eq,r0,-7
 RTCALL atoi,s100
 CHECK cc_eq,r0,100
 RTCALL strlen,shello
 CHECK cc_eq,r0,5
 RTCALL strlen,sempty
 CHECK cc_eq,r0,0
 RTCALL strcmp,sabc,sabc
 CHECK cc_eq,r0,0
 RTCALL strcmp,sabc,sabd
 CHECK cc_lt,r0,0
 RTCALL strcmp,sabd,sabc
 CHECK cc_gt,r0,0
; char buf[8]; strcpy(buf, "OK"); strcmp(buf, "OK") == 0
 LOCADDR r2,BUF
 RTCALL strcpy,r2,sok
 RTCALL strcmp,r2,sok
 CHECK cc_eq,r0,0
 CHECKEND "D41OK\n",42
 RET
 STR s42,"42"
 STR sm7,"-7"
 STR s100,"  100"
 STR shello,"hello"
 STR sempty,""
 STR sabc,"abc"
 STR sabd,"abd"
 STR sok,"OK"
COPY svc_bare_code
COPY rt_code
```

Output:

```
D41OK
r0=42
```

### demo50: a 256-byte local buffer

[`demo50.c`](../../sw-cor24-x-tinyc/demos/demo50.c) (37 lines; 1118 lines of tc24r assembly) →
[`demos/tinyc/demo50.hlasm`](../demos/tinyc/demo50.hlasm) (79 lines).
Macros: `LOCAL`, `LOCADDR` (offsets beyond -128), `MOD`, `REQUIRE`.

<details><summary>C source</summary>

```c
// tc24r demo50 -- large local array with nested function calls
//
// BUG-013 fix: char buf[256] on the stack caused offset overflow
// in lw/sw instructions (8-bit signed immediate range -128..127).
// Nested function calls would corrupt buf[0] because the store
// to buf[0] at offset -256 was truncated to offset 0 (saved fp).
//
// Expected: r0 = 50, UART output: "D50OK"

#include <stdio.h>

void fill(char *buf, int n) {
    int i;
    for (i = 0; i < n; i = i + 1) {
        buf[i] = 65 + (i % 26);
    }
}

int check(char *buf, int n) {
    int i;
    for (i = 0; i < n; i = i + 1) {
        if (buf[i] != 65 + (i % 26)) return 0;
    }
    return 1;
}

int main() {
    char buf[256];
    int sentinel;

    sentinel = 99;
    fill(buf, 256);

    // Nested calls between fill and check -- if the frame is corrupted,
    // sentinel or buf[0] will be wrong after the call returns.
    printf("");

    if (sentinel != 99) return 1;
    if (!check(buf, 256)) return 2;
    if (buf[0] != 65) return 3;
    if (buf[255] != 65 + (255 % 26)) return 4;

    printf("D50OK\n");
    return 50;
}
```

</details>

```
; demo50.c in hlasm: a 256-byte local buffer next to an int, filled and
; checked by routines. lw/sw offsets reach only -128..127, so the buffer
; is addressed with LOCADDR (tc24r's BUG-013 was exactly this). Returns
; 1-4 on a failed check, else prints "D50OK" and returns 50.
; Output: "D50OK" then "r0=50".
COPY cor24
COPY frame
COPY svc_bare
COPY check
COPY rt
SET SHOWRC,1
 START
_main:
 LOCAL SENT,3
 LOCAL BUF,256
 PROLOG
 la r0,99
 sw r0,SENT(fp)
 LOCADDR r2,BUF
 CALL _fill,r2,256
 lw r0,SENT(fp)
 REQUIRE cc_eq,r0,99,1
 LOCADDR r2,BUF
 CALL _check,r2,256
 REQUIRE cc_ne,r0,0,2
 lbu r0,0(r2)
 REQUIRE cc_eq,r0,65,3
 la r1,255
 add r2,r1
 lbu r0,0(r2)
 REQUIRE cc_eq,r0,65+255%26,4
 WTO "D50OK\n"
 RETURN 50

; _fill(buf, n): buf[i] = 'A' + i % 26
_fill:
 LOCAL FI_I,3
 PROLOG
 lc r0,0
 sw r0,FI_I(fp)
DO
 lw r0,FI_I(fp)
 ARG r1,2
 DOEXIT cc_ge,r0,r1
 MOD r0,26
 add r0,65
 ARG r2,1
 lw r1,FI_I(fp)
 add r2,r1
 sb r0,0(r2)
 add r1,1
 sw r1,FI_I(fp)
ENDDO
 RET

; _check(buf, n): 1 if every buf[i] == 'A' + i % 26, else 0
_check:
 LOCAL CK_I,3
 PROLOG
 lc r0,0
 sw r0,CK_I(fp)
DO
 lw r0,CK_I(fp)
 ARG r1,2
 DOEXIT cc_ge,r0,r1
 MOD r0,26
 add r0,65
 ARG r2,1
 lw r1,CK_I(fp)
 add r2,r1
 lbu r1,0(r2)
IF cc_ne,r0,r1
 RETURN 0
ENDIF
 lw r1,CK_I(fp)
 add r1,1
 sw r1,CK_I(fp)
ENDDO
 RETURN 1
COPY svc_bare_code
COPY rt_code
```

Output:

```
D50OK
r0=50
```

### demo51: function pointer variable

[`demo51.c`](../../sw-cor24-x-tinyc/demos/demo51.c) (20 lines; 985 lines of tc24r assembly) →
[`demos/tinyc/demo51.hlasm`](../demos/tinyc/demo51.hlasm) (32 lines).
Macros: `CALL r0,...`, `REQUIRE`.

<details><summary>C source</summary>

```c
// tc24r demo51 -- function pointer: basic variable call
//
// Assign a function to a pointer variable, call through the pointer.
//
// Expected: r0 = 51, UART output: "D51OK"

#include <stdio.h>

int add(int a, int b) {
    return a + b;
}

int main() {
    int (*fp)(int, int);
    fp = add;

    int result = fp(3, 4);
    if (result != 7) return 1;

    // Verify with a second call
    result = fp(20, 31);
    if (result != 51) return 2;

    printf("D51OK\n");
    return 51;
}
```

</details>

```
; demo51.c in hlasm: a function pointer in a local variable, called
; through r0 with CALL. Returns 1 or 2 on a failed check, else prints
; "D51OK" and returns 51. Output: "D51OK" then "r0=51".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1
 START
_main:
 LOCAL FPTR,3
 PROLOG
; fp = add
 la r0,_add
 sw r0,FPTR(fp)
; fp(3, 4) == 7
 lw r0,FPTR(fp)
 CALL r0,3,4
 REQUIRE cc_eq,r0,7,1
; fp(20, 31) == 51
 lw r0,FPTR(fp)
 CALL r0,20,31
 REQUIRE cc_eq,r0,51,2
 WTO "D51OK\n"
 RETURN 51

_add:
 PROLOG
 ARG r0,1
 ARG r1,2
 add r0,r1
 RET
COPY svc_bare_code
```

Output:

```
D51OK
r0=51
```

### demo52: function pointer table

[`demo52.c`](../../sw-cor24-x-tinyc/demos/demo52.c) (43 lines; 1159 lines of tc24r assembly) →
[`demos/tinyc/demo52.hlasm`](../demos/tinyc/demo52.hlasm) (79 lines).
Macros: `CALL r0,...` in a `DO` loop, `LOCADDR`, `REQUIRE`.

<details><summary>C source</summary>

```c
// tc24r demo52 -- function pointer: array dispatch table
//
// Store functions in an array, call through indexed array element.
//
// Expected: r0 = 52, UART output: "D52OK"

#include <stdio.h>

int double_it(int x) {
    return x + x;
}

int triple_it(int x) {
    return x + x + x;
}

int quad_it(int x) {
    return x + x + x + x;
}

int main() {
    int (*table[4])(int);
    table[0] = double_it;
    table[1] = triple_it;
    table[2] = quad_it;

    // double_it(5) = 10
    int r0 = table[0](5);
    if (r0 != 10) return 1;

    // triple_it(7) = 21
    int r1 = table[1](7);
    if (r1 != 21) return 2;

    // quad_it(3) = 12
    int r2 = table[2](3);
    if (r2 != 12) return 3;

    // sum = 10 + 21 + 12 = 43, need 52
    int sum = r0 + r1 + r2;
    if (sum != 43) return 4;

    // Loop dispatch: accumulate table[i](1) for i=0..2
    // double(1)=2, triple(1)=3, quad(1)=4 => 9
    int acc = 0;
    int i;
    for (i = 0; i < 3; i = i + 1) {
        acc = acc + table[i](1);
    }
    if (acc != 9) return 5;

    printf("D52OK\n");
    return 52;
}
```

</details>

```
; demo52.c in hlasm: a local table of function pointers, called by index
; directly and in a loop. Returns 1-5 on a failed check, else prints
; "D52OK" and returns 52. Output: "D52OK" then "r0=52".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1
 START
_main:
 LOCAL TBL,12
 LOCAL SUM,3
 LOCAL I,3
 PROLOG
; table[0..2] = double_it, triple_it, quad_it
 la r0,_double_it
 sw r0,TBL(fp)
 la r0,_triple_it
 sw r0,TBL+3(fp)
 la r0,_quad_it
 sw r0,TBL+6(fp)
; r0 = table[0](5) == 10; r1 = table[1](7) == 21; r2 = table[2](3) == 12
 lw r0,TBL(fp)
 CALL r0,5
 REQUIRE cc_eq,r0,10,1
 sw r0,SUM(fp)
 lw r0,TBL+3(fp)
 CALL r0,7
 REQUIRE cc_eq,r0,21,2
 lw r1,SUM(fp)
 add r0,r1
 sw r0,SUM(fp)
 lw r0,TBL+6(fp)
 CALL r0,3
 REQUIRE cc_eq,r0,12,3
 lw r1,SUM(fp)
 add r0,r1
 REQUIRE cc_eq,r0,43,4
; for (i = 0; i < 3; i++) acc = acc + table[i](1);
 lc r0,0
 sw r0,SUM(fp)
 sw r0,I(fp)
 LOCADDR r2,TBL
DO
 lw r0,I(fp)
 DOEXIT cc_ge,r0,3
 lw r0,0(r2)
 CALL r0,1
 lw r1,SUM(fp)
 add r0,r1
 sw r0,SUM(fp)
 add r2,3
 lw r0,I(fp)
 add r0,1
 sw r0,I(fp)
ENDDO
 lw r0,SUM(fp)
 REQUIRE cc_eq,r0,9,5
 WTO "D52OK\n"
 RETURN 52

_double_it:
 PROLOG
 ARG r0,1
 add r0,r0
 RET

_triple_it:
 PROLOG
 ARG r0,1
 mov r1,r0
 add r0,r0
 add r0,r1
 RET

_quad_it:
 PROLOG
 ARG r0,1
 add r0,r0
 add r0,r0
 RET
COPY svc_bare_code
```

Output:

```
D52OK
r0=52
```

### demo53: function pointer argument

[`demo53.c`](../../sw-cor24-x-tinyc/demos/demo53.c) (26 lines; 1041 lines of tc24r assembly) →
[`demos/tinyc/demo53.hlasm`](../demos/tinyc/demo53.hlasm) (41 lines).
Macros: `CALL _apply,_add,...`, `CALL r0,r2,r1`.

<details><summary>C source</summary>

```c
// tc24r demo53 -- function pointer: passed as parameter
//
// Pass a function pointer as an argument to another function.
//
// Expected: r0 = 53, UART output: "D53OK"

#include <stdio.h>

int add(int a, int b) {
    return a + b;
}

int sub(int a, int b) {
    return a - b;
}

int apply(int (*f)(int, int), int x, int y) {
    return f(x, y);
}

int main() {
    int r1 = apply(add, 30, 20);
    if (r1 != 50) return 1;

    int r2 = apply(sub, 30, 20);
    if (r2 != 10) return 2;

    // 50 + 10 = 60, but we want 53
    int r3 = apply(add, r1, 3);
    if (r3 != 53) return 3;

    printf("D53OK\n");
    return 53;
}
```

</details>

```
; demo53.c in hlasm: a function pointer passed as an argument and called
; by the callee. Returns 1-3 on a failed check, else prints "D53OK" and
; returns 53. Output: "D53OK" then "r0=53".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1
 START
_main:
 PROLOG
 CALL _apply,_add,30,20
 REQUIRE cc_eq,r0,50,1
 mov r2,r0
 CALL _apply,_sub,30,20
 REQUIRE cc_eq,r0,10,2
 CALL _apply,_add,r2,3
 REQUIRE cc_eq,r0,53,3
 WTO "D53OK\n"
 RETURN 53

; _apply(f, x, y) = f(x, y)
_apply:
 PROLOG
 ARG r0,1
 ARG r2,2
 ARG r1,3
 CALL r0,r2,r1
 RET

_add:
 PROLOG
 ARG r0,1
 ARG r1,2
 add r0,r1
 RET

_sub:
 PROLOG
 ARG r0,1
 ARG r1,2
 sub r0,r1
 RET
COPY svc_bare_code
```

Output:

```
D53OK
r0=53
```

### demo54: global function pointer

[`demo54.c`](../../sw-cor24-x-tinyc/demos/demo54.c) (25 lines; no tc24r assembly checked in) →
[`demos/tinyc/demo54.hlasm`](../demos/tinyc/demo54.hlasm) (42 lines).
Macros: `WORDS`, `CALL r0,...`, `mul`.

<details><summary>C source</summary>

```c
// tc24r demo54 -- global function pointer declaration
//
// Declare function pointers at global scope (not just local).
//
// Expected: r0 = 54, UART output: "D54OK"

#include <stdio.h>

int add(int a, int b) {
    return a + b;
}

int mul(int a, int b) {
    return a * b;
}

int (*op)(int, int);

int main() {
    // Assign and call through global function pointer
    op = add;
    int r1 = op(20, 30);
    if (r1 != 50) return 1;

    // Reassign to a different function
    op = mul;
    int r2 = op(6, 9);
    if (r2 != 54) return 2;

    printf("D54OK\n");
    return 54;
}
```

</details>

```
; demo54.c in hlasm: a global function pointer, reassigned and called.
; Returns 1 or 2 on a failed check, else prints "D54OK" and returns 54.
; Output: "D54OK" then "r0=54".
COPY cor24
COPY frame
COPY svc_bare
COPY data
COPY check
SET SHOWRC,1
 START
_main:
 PROLOG
; op = add; op(20, 30) == 50
 la r1,_op
 la r0,_add
 sw r0,0(r1)
 lw r0,0(r1)
 CALL r0,20,30
 REQUIRE cc_eq,r0,50,1
; op = mul; op(6, 9) == 54
 la r1,_op
 la r0,_mul
 sw r0,0(r1)
 lw r0,0(r1)
 CALL r0,6,9
 REQUIRE cc_eq,r0,54,2
 WTO "D54OK\n"
 RETURN 54
 WORDS _op,0

_add:
 PROLOG
 ARG r0,1
 ARG r1,2
 add r0,r1
 RET

_mul:
 PROLOG
 ARG r0,1
 ARG r1,2
 mul r0,r1
 RET
COPY svc_bare_code
```

Output:

```
D54OK
r0=54
```

### demo58: initialised global data

[`demo58.c`](../../sw-cor24-x-tinyc/demos/demo58.c) (50 lines; 1363 lines of tc24r assembly) →
[`demos/tinyc/demo58.hlasm`](../demos/tinyc/demo58.hlasm) (95 lines).
Macros: `STR`, `WORDS`, `BYTES`, `REQUIRE` with expressions.

<details><summary>C source</summary>

```c
// tc24r demo58 -- global data initialization
//
// Exercises static/global array initialization with string literals
// and initializer lists, including char and int arrays, zero-padding,
// and runtime access.
//
// Expected: r0 = 58, UART output: "D58OK"

#include <stdio.h>

static const char greeting[] = "hello";
int fib_table[] = {1, 1, 2, 3, 5, 8, 13, 21};
char vowels[] = {'A', 'E', 'I', 'O', 'U', 0};
int sparse[5] = {100, 200};

int test_string_init(void) {
    if (greeting[0] != 'h') return 1;
    if (greeting[4] != 'o') return 2;
    if (greeting[5] != '\0') return 3;
    return greeting[0] + greeting[1] + greeting[2];
}

int test_int_init_list(void) {
    if (fib_table[0] != 1) return 1;
    if (fib_table[5] != 8) return 2;
    if (fib_table[7] != 21) return 3;
    return fib_table[0] + fib_table[1] + fib_table[2];
}

int test_char_init_list(void) {
    if (vowels[0] != 'A') return 1;
    if (vowels[4] != 'U') return 2;
    if (vowels[5] != '\0') return 3;
    return vowels[0] + vowels[1] + vowels[2] + vowels[3] + vowels[4];
}

int test_zero_padding(void) {
    if (sparse[0] != 100) return 1;
    if (sparse[1] != 200) return 2;
    if (sparse[2] != 0) return 3;
    if (sparse[4] != 0) return 4;
    return sparse[0] + sparse[1];
}

int main() {
    int r = 0;

    r = test_string_init();
    if (r != 104 + 101 + 108) return 1;

    r = test_int_init_list();
    if (r != 4) return 2;

    r = test_char_init_list();
    if (r != 'A' + 'E' + 'I' + 'O' + 'U') return 3;

    r = test_zero_padding();
    if (r != 300) return 4;

    printf("D58OK\n");
    return 58;
}
```

</details>

```
; demo58.c in hlasm: initialised global data -- a string, an int table,
; a char table and a partly initialised int array (the rest zero) -- as
; STR, WORDS and BYTES. Returns 1-4 on a failed check, else prints "D58OK"
; and returns 58. Output: "D58OK" then "r0=58".
COPY cor24
COPY frame
COPY svc_bare
COPY data
COPY check
SET SHOWRC,1
 START
_main:
 PROLOG
 CALL _test_string_init
 REQUIRE cc_eq,r0,104+101+108,1
 CALL _test_int_init_list
 REQUIRE cc_eq,r0,4,2
 CALL _test_char_init_list
 REQUIRE cc_eq,r0,'A'+'E'+'I'+'O'+'U',3
 CALL _test_zero_padding
 REQUIRE cc_eq,r0,300,4
 WTO "D58OK\n"
 RETURN 58

; greeting[0] + greeting[1] + greeting[2], after checking three bytes
_test_string_init:
 PROLOG
 la r2,greeting
 lbu r0,0(r2)
 REQUIRE cc_eq,r0,'h',1
 lbu r0,4(r2)
 REQUIRE cc_eq,r0,'o',2
 lbu r0,5(r2)
 REQUIRE cc_eq,r0,0,3
 lbu r0,0(r2)
 lbu r1,1(r2)
 add r0,r1
 lbu r1,2(r2)
 add r0,r1
 RET

_test_int_init_list:
 PROLOG
 la r2,fib_table
 lw r0,0(r2)
 REQUIRE cc_eq,r0,1,1
 lw r0,15(r2)
 REQUIRE cc_eq,r0,8,2
 lw r0,21(r2)
 REQUIRE cc_eq,r0,21,3
 lw r0,0(r2)
 lw r1,3(r2)
 add r0,r1
 lw r1,6(r2)
 add r0,r1
 RET

_test_char_init_list:
 PROLOG
 la r2,vowels
 lbu r0,0(r2)
 REQUIRE cc_eq,r0,'A',1
 lbu r0,4(r2)
 REQUIRE cc_eq,r0,'U',2
 lbu r0,5(r2)
 REQUIRE cc_eq,r0,0,3
 lc r0,0
 lbu r1,0(r2)
 add r0,r1
 lbu r1,1(r2)
 add r0,r1
 lbu r1,2(r2)
 add r0,r1
 lbu r1,3(r2)
 add r0,r1
 lbu r1,4(r2)
 add r0,r1
 RET

_test_zero_padding:
 PROLOG
 la r2,sparse
 lw r0,0(r2)
 REQUIRE cc_eq,r0,100,1
 lw r0,3(r2)
 REQUIRE cc_eq,r0,200,2
 lw r0,6(r2)
 REQUIRE cc_eq,r0,0,3
 lw r0,12(r2)
 REQUIRE cc_eq,r0,0,4
 lw r0,0(r2)
 lw r1,3(r2)
 add r0,r1
 RET

 STR greeting,"hello"
 WORDS fib_table,1,1,2,3,5,8,13,21
 BYTES vowels,'A','E','I','O','U',0
 WORDS sparse,100,200,0,0,0
COPY svc_bare_code
```

Output:

```
D58OK
r0=58
```

### demo63: adjacent string literals

[`demo63.c`](../../sw-cor24-x-tinyc/demos/demo63.c) (54 lines; no tc24r assembly checked in) →
[`demos/tinyc/demo63.hlasm`](../demos/tinyc/demo63.hlasm) (90 lines).
Macros: consecutive `.ascii` lines, runtime sizes from labels, `RTCALL memset/strcpy/strlen`.

<details><summary>C source</summary>

```c
// tc24r demo63 -- adjacent string-literal concatenation (C99 phase 6)
//                  + char-storage init (pr/codegen-string-storage-bugs)
//
// Verifies end-to-end:
//   - basic two-chunk concat in a return expression
//   - N-chunk concat across newlines, indexed via function-return ptr
//   - per-chunk escape resolution: "ab\n" "cd" yields a single 6-byte
//     literal in .data with the bytes {a,b,'\n',c,d,0}
//   - concat in a function-call argument
//   - sizeof(char arr[] = "abc" "def") reports 7, not 4 — both global
//     and local
//   - char *global = "..." indexing reads the string bytes
//   - char local[] = "..." indexing reads the string bytes (zero-pad
//     for explicit size)
//
// Expected: r0 = 63, UART output: "D63OK"

#include <stdio.h>

/* Global char array — bytes-in-place storage. */
char g_arr[] = "abc" "def";

/* Global char pointer — must store the address of an anonymous rodata
   literal, NOT the bytes inline. */
char *g_ptr = "ab\n" "cd";

char *greeting(void) {
    return "hello, "
           "world!"
           " "
           "D63";
}

int main(void) {
    /* Per-chunk escape resolution via global pointer (bug 1 path). */
    if (g_ptr[0] != 'a' || g_ptr[1] != 'b' || g_ptr[2] != '\n'
        || g_ptr[3] != 'c' || g_ptr[4] != 'd' || g_ptr[5] != 0) {
        return 1;
    }

    /* Global implicit-size: sizeof(g_arr) must use the concatenated
       length (7 = 6 chars + null), not 4 (just "abc" + null). */
    if (sizeof(g_arr) != 7) return 2;
    if (g_arr[0] != 'a' || g_arr[5] != 'f' || g_arr[6] != 0) return 3;

    /* Local implicit-size: sizeof + byte-level access (bug 2 path). */
    char local[] = "ab" "cd" "ef" "gh";
    if (sizeof(local) != 9) return 4;
    if (local[0] != 'a' || local[7] != 'h' || local[8] != 0) return 5;

    /* Local explicit-size with zero pad — char[10] = "abc". */
    char padded[10] = "abc";
    if (padded[0] != 'a' || padded[2] != 'c' || padded[3] != 0) return 6;
    if (padded[9] != 0) return 7; /* trailing zero pad */

    /* Function returning a multi-chunk concatenated string. */
    char *gr = greeting();
    if (gr[0] != 'h' || gr[7] != 'w' || gr[13] != ' ') return 8;
    if (gr[14] != 'D' || gr[15] != '6' || gr[16] != '3' || gr[17] != 0) return 9;

    /* In a function call argument. */
    printf("D63" "OK\n");
    return 63;
}
```

</details>

```
; demo63.c in hlasm: C joins adjacent string literals; in assembly that is
; simply consecutive .ascii lines before the terminating .byte 0. Sizes
; that C gets from sizeof are measured here at run time (end label minus
; start). Returns 1-9 on a failed check, else prints "D63OK" and returns
; 63. Output: "D63OK" then "r0=63".
COPY cor24
COPY frame
COPY svc_bare
COPY data
COPY check
COPY rt
SET SHOWRC,1
 START
_main:
 LOCAL LOCALS,9
 LOCAL PADDED,10
 PROLOG
; g_ptr points at "ab\n" "cd"
 la r1,g_ptr
 lw r2,0(r1)
 lbu r0,0(r2)
 REQUIRE cc_eq,r0,'a',1
 lbu r0,2(r2)
 REQUIRE cc_eq,r0,'\n',1
 lbu r0,4(r2)
 REQUIRE cc_eq,r0,'d',1
 lbu r0,5(r2)
 REQUIRE cc_eq,r0,0,1
; sizeof(g_arr) == 7: the bytes from g_arr to g_arr_end
 la r0,g_arr_end
 la r1,g_arr
 sub r0,r1
 REQUIRE cc_eq,r0,7,2
 la r2,g_arr
 lbu r0,5(r2)
 REQUIRE cc_eq,r0,'f',3
 lbu r0,6(r2)
 REQUIRE cc_eq,r0,0,3
; char local[] = "ab" "cd" "ef" "gh": 8 characters and the NUL
 LOCADDR r2,LOCALS
 RTCALL strcpy,r2,abcdefgh
 RTCALL strlen,r2
 REQUIRE cc_eq,r0,8,4
 lbu r0,7(r2)
 REQUIRE cc_eq,r0,'h',5
; char padded[10] = "abc": the rest is zero
 LOCADDR r2,PADDED
 RTCALL memset,r2,0,10
 RTCALL strcpy,r2,abc
 lbu r0,2(r2)
 REQUIRE cc_eq,r0,'c',6
 lbu r0,9(r2)
 REQUIRE cc_eq,r0,0,7
; greeting() returns "hello, " "world!" " " "D63"
 CALL _greeting
 mov r2,r0
 lbu r0,7(r2)
 REQUIRE cc_eq,r0,'w',8
 lbu r0,13(r2)
 REQUIRE cc_eq,r0,' ',8
 lbu r0,16(r2)
 REQUIRE cc_eq,r0,'3',9
 lbu r0,17(r2)
 REQUIRE cc_eq,r0,0,9
 WTO "D63"
 WTO "OK\n"
 RETURN 63

_greeting:
 PROLOG
 RETURN greeting_lit

g_arr:
 .ascii "abc"
 .ascii "def"
 .byte 0
g_arr_end:
 WORDS g_ptr,g_ptr_lit
g_ptr_lit:
 .ascii "ab\n"
 .ascii "cd"
 .byte 0
greeting_lit:
 .ascii "hello, "
 .ascii "world!"
 .ascii " "
 .ascii "D63"
 .byte 0
 STR abcdefgh,"abcdefgh"
 STR abc,"abc"
COPY svc_bare_code
COPY rt_code
```

Output:

```
D63OK
r0=63
```

### Batch 4: structs, unions, heap (step 17)

These use the record-layout macros from `lib/struct.hlasm` (`DSECT`/`USECT`/`FIELD`/`DEND`): a field name is its offset, so `s.a` on a local is `S+s_a(fp)` and `p->val` through a pointer in r2 is `nd_val(r2)`.

### demo23: enum

[`demo23.c`](../../sw-cor24-x-tinyc/demos/demo23.c) (35 lines; 142 lines of tc24r assembly) →
[`demos/tinyc/demo23.hlasm`](../demos/tinyc/demo23.hlasm) (52 lines).
Macros: a demo-local `ENUM` macro (auto-numbered `EQU`s), `EQU` expressions.

<details><summary>C source</summary>

```c
// tc24r demo23 -- enum
//
// New features:
//   - enum { A, B, C } -- auto-incrementing constants
//   - enum { X=5, Y, Z } -- explicit values
//   - enum tag { ... } -- named enum types
//   - enum constants resolve to int at parse time
//
// Expected: r0 = 42, UART output: "D23OK"

#define UART_DATA 0xFF0100
#define UART_STATUS 0xFF0101
void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

enum color { RED, GREEN, BLUE };

int main() {
    int ok = 1;

    // auto-increment
    if (RED != 0) ok = 0;
    if (GREEN != 1) ok = 0;
    if (BLUE != 2) ok = 0;

    // explicit values
    enum { OFF = 0, ON = 1, AUTO = 10 };
    if (AUTO != 10) ok = 0;

    // in expressions
    int x = GREEN + BLUE;
    if (x != 3) ok = 0;

    // in statement expression
    int y = ({ enum { A=20, B }; B; });
    if (y != 21) ok = 0;

    if (ok) {
        puts("D23OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo23.c in hlasm: an enum is a run of EQU symbols. A demo-local ENUM
; macro numbers its names from a start value, as C does. Prints "D23OK"
; and returns 42. Output: "D23OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1

; ENUM first,n1[,...,n6]: n1 = first, n2 = first + 1, ...
MACRO ENUM &F,&N1,&N2,&N3,&N4,&N5,&N6
SET EN_V,&F
 ENUMONE &N1
 ENUMONE &N2
 ENUMONE &N3
 ENUMONE &N4
 ENUMONE &N5
 ENUMONE &N6
MEND

MACRO ENUMONE &N
IFDIFF &N,
&N EQU EN_V
SET EN_V,EN_V+1
ENDIFASM
MEND

; enum color { RED, GREEN, BLUE };
 ENUM 0,RED,GREEN,BLUE
; enum { OFF = 0, ON = 1, AUTO = 10 };
OFF EQU 0
ON EQU 1
AUTO EQU 10
; ({ enum { A = 20, B }; B; })
 ENUM 20,EA,EB

 START
_main:
 PROLOG
 CHECKINIT
 la r0,RED
 CHECK cc_eq,r0,0
 la r0,GREEN
 CHECK cc_eq,r0,1
 la r0,BLUE
 CHECK cc_eq,r0,2
 la r0,AUTO
 CHECK cc_eq,r0,10
; int x = GREEN + BLUE;
 la r0,GREEN+BLUE
 CHECK cc_eq,r0,3
 la r0,EB
 CHECK cc_eq,r0,21
 CHECKEND "D23OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
D23OK
r0=42
```

### demo25: struct

[`demo25.c`](../../sw-cor24-x-tinyc/demos/demo25.c) (45 lines; 199 lines of tc24r assembly) →
[`demos/tinyc/demo25.hlasm`](../demos/tinyc/demo25.hlasm) (57 lines).
Macros: `DSECT`/`FIELD`/`DEND`, `LOCAL name,SIZEOF_...`, displacements `P+pt_x(fp)`.

<details><summary>C source</summary>

```c
// tc24r demo25 -- struct support
//
// New features:
//   - struct { type member; ... } definition
//   - struct tag { ... } named struct
//   - struct tag var; variable declaration
//   - var.member read and write
//   - sizeof(struct tag)
//
// Expected: r0 = 42, UART output: "D25OK"

#define UART_DATA 0xFF0100
#define UART_STATUS 0xFF0101
void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

struct point {
    int x;
    int y;
};

int main() {
    int ok = 1;

    // anonymous struct
    struct { int a; int b; } s;
    s.a = 10;
    s.b = 20;
    if (s.a + s.b != 30) ok = 0;

    // named struct
    struct point p;
    p.x = 3;
    p.y = 4;
    if (p.x != 3) ok = 0;
    if (p.y != 4) ok = 0;

    // sizeof
    if (sizeof(struct point) != 6) ok = 0;

    // struct in expression
    int sum = p.x + p.y;
    if (sum != 7) ok = 0;

    // compound assignment on member
    p.x += 10;
    if (p.x != 13) ok = 0;

    if (ok) {
        puts("D25OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo25.c in hlasm: structs as DSECT layouts; a local struct is a LOCAL
; of SIZEOF bytes, and s.a is the displacement S+s_a from fp.
; Prints "D25OK" and returns 42. Output: "D25OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
COPY struct
SET SHOWRC,1

 DSECT point
 FIELD pt_x,3
 FIELD pt_y,3
 DEND point

; the anonymous struct { int a; int b; }
 DSECT ab
 FIELD s_a,3
 FIELD s_b,3
 DEND ab

 START
_main:
 LOCAL S,SIZEOF_ab
 LOCAL P,SIZEOF_point
 PROLOG
 CHECKINIT
; s.a = 10; s.b = 20;  s.a + s.b == 30
 lc r0,10
 sw r0,S+s_a(fp)
 lc r0,20
 sw r0,S+s_b(fp)
 lw r0,S+s_a(fp)
 lw r1,S+s_b(fp)
 add r0,r1
 CHECK cc_eq,r0,30
; p.x = 3; p.y = 4;
 lc r0,3
 sw r0,P+pt_x(fp)
 lc r0,4
 sw r0,P+pt_y(fp)
 lw r0,P+pt_x(fp)
 CHECK cc_eq,r0,3
 lw r0,P+pt_y(fp)
 CHECK cc_eq,r0,4
; sizeof(struct point) == 6
 la r0,SIZEOF_point
 CHECK cc_eq,r0,6
 lw r0,P+pt_x(fp)
 lw r1,P+pt_y(fp)
 add r0,r1
 CHECK cc_eq,r0,7
; p.x += 10;
 lw r0,P+pt_x(fp)
 add r0,10
 sw r0,P+pt_x(fp)
 CHECK cc_eq,r0,13
 CHECKEND "D25OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
D25OK
r0=42
```

### demo28: union

[`demo28.c`](../../sw-cor24-x-tinyc/demos/demo28.c) (39 lines; 183 lines of tc24r assembly) →
[`demos/tinyc/demo28.hlasm`](../demos/tinyc/demo28.hlasm) (44 lines).
Macros: `USECT` (all members at 0, size of the largest).

<details><summary>C source</summary>

```c
// tc24r demo28 -- union support
//
// New features:
//   - union { type member; ... } definition
//   - union tag { ... } named union
//   - Members share same memory (offset 0)
//   - sizeof(union) = max member size
//
// Expected: r0 = 42, UART output: "D28OK"

#define UART_DATA 0xFF0100
#define UART_STATUS 0xFF0101
void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

union intchar {
    int i;
    char c;
};

int main() {
    int ok = 1;

    // basic union: members share same memory
    union intchar u;
    u.i = 42;
    if (u.i != 42) ok = 0;

    // writing to one member affects the other (same offset)
    u.i = 65;
    if (u.c != 65) ok = 0;

    // sizeof union = max member size (int=3, char=1, so 3)
    if (sizeof(union intchar) != 3) ok = 0;

    // anonymous union
    union { int x; int y; } v;
    v.x = 100;
    // x and y share same memory
    if (v.y != 100) ok = 0;

    if (ok) {
        puts("D28OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo28.c in hlasm: unions as USECT layouts -- every member at offset 0,
; the size of the largest. Writing the int and reading the char gives its
; low byte (COR24 is little-endian). Prints "D28OK" and returns 42.
; Output: "D28OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
COPY struct
SET SHOWRC,1

 USECT intchar
 FIELD ic_i,3
 FIELD ic_c,1
 DEND intchar

; the anonymous union { int x; int y; }
 USECT xy
 FIELD u_x,3
 FIELD u_y,3
 DEND xy

 START
_main:
 LOCAL U,SIZEOF_intchar
 LOCAL V,SIZEOF_xy
 PROLOG
 CHECKINIT
 lc r0,42
 sw r0,U+ic_i(fp)
 lw r0,U+ic_i(fp)
 CHECK cc_eq,r0,42
; u.i = 65;  u.c == 65
 lc r0,65
 sw r0,U+ic_i(fp)
 lbu r0,U+ic_c(fp)
 CHECK cc_eq,r0,65
 la r0,SIZEOF_intchar
 CHECK cc_eq,r0,3
; v.x = 100;  v.y == 100
 la r0,100
 sw r0,V+u_x(fp)
 lw r0,V+u_y(fp)
 CHECK cc_eq,r0,100
 CHECKEND "D28OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
D28OK
r0=42
```

### demo34: two-dimensional arrays

[`demo34.c`](../../sw-cor24-x-tinyc/demos/demo34.c) (33 lines; 258 lines of tc24r assembly) →
[`demos/tinyc/demo34.hlasm`](../demos/tinyc/demo34.hlasm) (41 lines).
Macros: assembly-time size expressions, row-major displacement `A+(1*3+2)*3(fp)`.

<details><summary>C source</summary>

```c
// tc24r demo34 -- multi-dimensional array declarations
//
// New feature:
//   - int a[2][3]; (multi-dimensional array declaration)
//   - sizeof(int[N][M]) correct sizing
//
// Expected: r0 = 42, UART output: "D34OK"

#define UART_DATA 0xFF0100
#define UART_STATUS 0xFF0101
void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

int main() {
    int ok = 1;

    // multi-dimensional array sizeof
    if (sizeof(int[2][3]) != 18) ok = 0;
    if (sizeof(int[3][4]) != 36) ok = 0;
    if (sizeof(char[2][3]) != 6) ok = 0;

    // multi-dim array declaration allocates correct stack space
    int a[2][3];
    int *p = (int *)a;
    p[0] = 10;
    p[1] = 20;
    p[2] = 30;
    p[3] = 40;
    p[4] = 50;
    p[5] = 60;
    if (p[0] + p[5] != 70) ok = 0;

    if (ok) {
        puts("D34OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo34.c in hlasm: a two-dimensional array is rows*cols elements laid out
; row by row; sizes are assembly-time expressions. Prints "D34OK" and
; returns 42. Output: "D34OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
SET SHOWRC,1
 START
_main:
 LOCAL A,2*3*3
 PROLOG
 CHECKINIT
; sizeof(int[2][3]) == 18, sizeof(int[3][4]) == 36, sizeof(char[2][3]) == 6
 la r0,2*3*3
 CHECK cc_eq,r0,18
 la r0,3*4*3
 CHECK cc_eq,r0,36
 la r0,2*3*1
 CHECK cc_eq,r0,6
; int *p = (int *)a; p[0..5] = 10..60
 lc r0,10
 sw r0,A(fp)
 lc r0,20
 sw r0,A+3(fp)
 lc r0,30
 sw r0,A+6(fp)
 lc r0,40
 sw r0,A+9(fp)
 lc r0,50
 sw r0,A+12(fp)
 lc r0,60
 sw r0,A+15(fp)
; p[0] + p[5] == 70  (p[5] is a[1][2]: row 1, column 2)
 lw r0,A(fp)
 lw r1,A+(1*3+2)*3(fp)
 add r0,r1
 CHECK cc_eq,r0,70
 CHECKEND "D34OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
D34OK
r0=42
```

### demo35: arrays inside structs

[`demo35.c`](../../sw-cor24-x-tinyc/demos/demo35.c) (35 lines; 151 lines of tc24r assembly) →
[`demos/tinyc/demo35.hlasm`](../demos/tinyc/demo35.hlasm) (34 lines).
Macros: `FIELD rc_tag,4*1` (an array member), `SIZEOF_`.

<details><summary>C source</summary>

```c
// tc24r demo35 -- struct array members
//
// New feature:
//   - struct { char a[3]; int b; } (array members in structs)
//   - sizeof(struct tag) correctly accounts for array member sizes
//
// Expected: r0 = 42, UART output: "D35OK"

#define UART_DATA 0xFF0100
#define UART_STATUS 0xFF0101
void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

struct record {
    char tag[4];
    int value;
};

struct pair {
    char a[3];
    char b[5];
};

int main() {
    int ok = 1;

    // sizeof with array member: char[4] + int = 4 + 3 = 7
    if (sizeof(struct record) != 7) ok = 0;

    // sizeof with multiple array members: char[3] + char[5] = 8
    if (sizeof(struct pair) != 8) ok = 0;

    // struct with array member - access scalar after array
    struct record r;
    r.value = 42;
    if (r.value != 42) ok = 0;

    if (ok) {
        puts("D35OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo35.c in hlasm: array members in a struct take their full size in the
; layout (FIELD rc_tag,4 for char tag[4]). Prints "D35OK" and returns 42.
; Output: "D35OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
COPY struct
SET SHOWRC,1

 DSECT record
 FIELD rc_tag,4*1
 FIELD rc_value,3
 DEND record

 DSECT pair
 FIELD pr_a,3*1
 FIELD pr_b,5*1
 DEND pair

 START
_main:
 LOCAL R,SIZEOF_record
 PROLOG
 CHECKINIT
 la r0,SIZEOF_record
 CHECK cc_eq,r0,7
 la r0,SIZEOF_pair
 CHECK cc_eq,r0,8
; r.value = 42
 lc r0,42
 sw r0,R+rc_value(fp)
 lw r0,R+rc_value(fp)
 CHECK cc_eq,r0,42
 CHECKEND "D35OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
D35OK
r0=42
```

### demo38: struct initialisers

[`demo38.c`](../../sw-cor24-x-tinyc/demos/demo38.c) (31 lines; 229 lines of tc24r assembly) →
[`demos/tinyc/demo38.hlasm`](../demos/tinyc/demo38.hlasm) (55 lines).
Macros: a demo-local `INIT2` macro storing members.

<details><summary>C source</summary>

```c
// tc24r demo38 -- struct brace initializer
//
// New feature:
//   - struct point p = {3, 4}; (brace initializer)
//   - Desugars to declaration + member assignments
//
// Expected: r0 = 42, UART output: "D38OK"

#define UART_DATA 0xFF0100
#define UART_STATUS 0xFF0101
void putc(int c) { while (*(char *)UART_STATUS & 0x80) {} *(char *)UART_DATA = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }

struct point { int x; int y; };

int main() {
    int ok = 1;

    // basic brace initializer
    struct point p = {3, 4};
    if (p.x != 3) ok = 0;
    if (p.y != 4) ok = 0;

    // trailing comma allowed
    struct point q = {10, 20,};
    if (q.x + q.y != 30) ok = 0;

    // partial initializer (fewer values than members)
    struct { int a; int b; int c; } s = {1, 2};
    if (s.a != 1) ok = 0;
    if (s.b != 2) ok = 0;

    if (ok) {
        puts("D38OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo38.c in hlasm: a struct initialiser is a store per member; members
; without an initialiser are set to 0. Prints "D38OK" and returns 42.
; Output: "D38OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
COPY struct
SET SHOWRC,1

 DSECT point
 FIELD pt_x,3
 FIELD pt_y,3
 DEND point

 DSECT abc
 FIELD s_a,3
 FIELD s_b,3
 FIELD s_c,3
 DEND abc

; INIT2 local,field1,value1,field2,value2: initialise two members
MACRO INIT2 &L,&F1,&V1,&F2,&V2
 la r0,&V1
 sw r0,&L+&F1(fp)
 la r0,&V2
 sw r0,&L+&F2(fp)
MEND

 START
_main:
 LOCAL P,SIZEOF_point
 LOCAL Q,SIZEOF_point
 LOCAL S,SIZEOF_abc
 PROLOG
 CHECKINIT
; struct point p = {3, 4};
 INIT2 P,pt_x,3,pt_y,4
 lw r0,P+pt_x(fp)
 CHECK cc_eq,r0,3
 lw r0,P+pt_y(fp)
 CHECK cc_eq,r0,4
; struct point q = {10, 20,};
 INIT2 Q,pt_x,10,pt_y,20
 lw r0,Q+pt_x(fp)
 lw r1,Q+pt_y(fp)
 add r0,r1
 CHECK cc_eq,r0,30
; struct { int a; int b; int c; } s = {1, 2};  (c is 0)
 INIT2 S,s_a,1,s_b,2
 lc r0,0
 sw r0,S+s_c(fp)
 lw r0,S+s_a(fp)
 CHECK cc_eq,r0,1
 lw r0,S+s_b(fp)
 CHECK cc_eq,r0,2
 CHECKEND "D38OK\n",42
 RET
COPY svc_bare_code
```

Output:

```
D38OK
r0=42
```

### demo40: malloc, calloc, free

[`demo40.c`](../../sw-cor24-x-tinyc/demos/demo40.c) (35 lines; 1638 lines of tc24r assembly) →
[`demos/tinyc/demo40.hlasm`](../demos/tinyc/demo40.hlasm) (47 lines).
Macros: `GETMAIN`, `FREEMAIN`, `RTCALL memset`.

<details><summary>C source</summary>

```c
// tc24r demo40 -- malloc/free (stdlib.h)
//
// New features:
//   - #include <stdlib.h> with bump allocator
//   - malloc(size), free(ptr), calloc(n, size)
//
// Expected: r0 = 42, UART output: "D40OK"

#include <stdio.h>
#include <stdlib.h>

int main() {
    int ok = 1;

    // malloc and use
    int *p = (int *)malloc(3);
    *p = 10;
    if (*p != 10) ok = 0;
    free(p);

    // malloc array
    int *arr = (int *)malloc(12);
    arr[0] = 1;
    arr[1] = 2;
    arr[2] = 3;
    arr[3] = 4;
    if (arr[0] + arr[3] != 5) ok = 0;
    free(arr);

    // calloc (zero-initialized)
    char *buf = (char *)calloc(4, 1);
    if (buf[0] != 0) ok = 0;
    if (buf[3] != 0) ok = 0;
    free(buf);

    if (ok) {
        printf("D40OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo40.c in hlasm: malloc is GETMAIN (a bump allocator, like tc24r's),
; free is FREEMAIN, calloc is GETMAIN plus memset. Prints "D40OK" and
; returns 42. Output: "D40OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
COPY rt
SET SHOWRC,1
 START
_main:
 PROLOG
 CHECKINIT
; int *p = malloc(3); *p = 10;
 GETMAIN r2,3
 lc r0,10
 sw r0,0(r2)
 lw r0,0(r2)
 CHECK cc_eq,r0,10
 FREEMAIN r2,3
; int *arr = malloc(12); arr[0..3] = 1..4;  arr[0] + arr[3] == 5
 GETMAIN r2,12
 lc r0,1
 sw r0,0(r2)
 lc r0,2
 sw r0,3(r2)
 lc r0,3
 sw r0,6(r2)
 lc r0,4
 sw r0,9(r2)
 lw r0,0(r2)
 lw r1,9(r2)
 add r0,r1
 CHECK cc_eq,r0,5
 FREEMAIN r2,12
; char *buf = calloc(4, 1);
 GETMAIN r2,4
 RTCALL memset,r2,0,4
 lbu r0,0(r2)
 CHECK cc_eq,r0,0
 lbu r0,3(r2)
 CHECK cc_eq,r0,0
 FREEMAIN r2,4
 CHECKEND "D40OK\n",42
 RET
COPY svc_bare_code
COPY rt_code
```

Output:

```
D40OK
r0=42
```

### demo42: linked list

[`demo42.c`](../../sw-cor24-x-tinyc/demos/demo42.c) (42 lines; 1831 lines of tc24r assembly) →
[`demos/tinyc/demo42.hlasm`](../demos/tinyc/demo42.hlasm) (59 lines).
Macros: `DSECT node`, `LOCADDR`, loads through `nd_next(r2)`.

<details><summary>C source</summary>

```c
// tc24r demo42 -- nested struct member access (linked list)
//
// New feature:
//   - a.next->val (chained dot + arrow access)
//   - a->b->c (multi-level arrow traversal)
//   - Codegen resolves struct types through expression chains
//
// Expected: r0 = 42, UART output: "D42OK"

#include <stdio.h>
#include <stdlib.h>

struct node {
    int val;
    struct node *next;
};

int sum_list(struct node *p) {
    int total = 0;
    while (p != (struct node *)0) {
        total = total + p->val;
        p = p->next;
    }
    return total;
}

int main() {
    int ok = 1;

    // Build a linked list: 10 -> 20 -> 12
    struct node a;
    struct node b;
    struct node c;
    a.val = 10; a.next = &b;
    b.val = 20; b.next = &c;
    c.val = 12; c.next = (struct node *)0;

    // Chained access
    if (a.next->val != 20) ok = 0;
    if (a.next->next->val != 12) ok = 0;

    // Walk the list
    if (sum_list(&a) != 42) ok = 0;

    if (ok) {
        printf("D42OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo42.c in hlasm: a linked list of local nodes; p->next->val is two
; loads through the layout's displacements. Prints "D42OK" and returns 42.
; Output: "D42OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
COPY struct
SET SHOWRC,1

 DSECT node
 FIELD nd_val,3
 FIELD nd_next,3
 DEND node

 START
_main:
 LOCAL NA,SIZEOF_node
 LOCAL NB,SIZEOF_node
 LOCAL NC,SIZEOF_node
 PROLOG
 CHECKINIT
; a.val = 10; a.next = &b;  b.val = 20; b.next = &c;  c.val = 12; c.next = 0;
 lc r0,10
 sw r0,NA+nd_val(fp)
 LOCADDR r2,NB
 sw r2,NA+nd_next(fp)
 lc r0,20
 sw r0,NB+nd_val(fp)
 LOCADDR r2,NC
 sw r2,NB+nd_next(fp)
 lc r0,12
 sw r0,NC+nd_val(fp)
 lc r0,0
 sw r0,NC+nd_next(fp)
; a.next->val == 20; a.next->next->val == 12
 lw r2,NA+nd_next(fp)
 lw r0,nd_val(r2)
 CHECK cc_eq,r0,20
 lw r2,nd_next(r2)
 lw r0,nd_val(r2)
 CHECK cc_eq,r0,12
; sum_list(&a) == 42
 LOCADDR r2,NA
 CALL _sum_list,r2
 CHECK cc_eq,r0,42
 CHECKEND "D42OK\n",42
 RET

; _sum_list(p): the sum of val over the list starting at p
_sum_list:
 PROLOG
 ARG r2,1
 lc r0,0
DO
 DOEXIT cc_eq,r2,0
 lw r1,nd_val(r2)
 add r0,r1
 lw r2,nd_next(r2)
ENDDO
 RET
COPY svc_bare_code
```

Output:

```
D42OK
r0=42
```

### demo43: cons cells on the heap

[`demo43.c`](../../sw-cor24-x-tinyc/demos/demo43.c) (49 lines; 1951 lines of tc24r assembly) →
[`demos/tinyc/demo43.hlasm`](../demos/tinyc/demo43.hlasm) (87 lines).
Macros: `GETMAIN r2,SIZEOF_cell`, `RETURN r2`, a demo-local `CONSNUM` macro.

<details><summary>C source</summary>

```c
// tc24r demo43 -- Lisp-style cons cells (struct pointer return + nested access)
//
// New features:
//   - Functions returning struct pointers (struct val *make())
//   - Nested arrow access through malloc'd structs
//   - Cons cell pattern: car/cdr linked list
//
// Expected: r0 = 42, UART output: "D43OK"

#include <stdio.h>
#include <stdlib.h>

struct val { int tag; int num; struct val *car; struct val *cdr; };

struct val *make_num(int n) {
    struct val *v = (struct val *)malloc(12);
    v->tag = 0;
    v->num = n;
    return v;
}

struct val *cons(struct val *a, struct val *d) {
    struct val *v = (struct val *)malloc(12);
    v->tag = 1;
    v->car = a;
    v->cdr = d;
    return v;
}

int main() {
    int ok = 1;

    // Build list: (1 2 3)
    struct val *nil = make_num(0);
    struct val *lst = cons(make_num(1), cons(make_num(2), cons(make_num(3), nil)));

    // car = 1
    if (lst->car->num != 1) ok = 0;
    // cadr = 2
    if (lst->cdr->car->num != 2) ok = 0;
    // caddr = 3
    if (lst->cdr->cdr->car->num != 3) ok = 0;

    // Sum the list
    int sum = 0;
    struct val *p = lst;
    while (p->tag == 1) {
        sum = sum + p->car->num;
        p = p->cdr;
    }
    if (sum != 6) ok = 0;

    if (ok) {
        printf("D43OK\n");
        return 42;
    }
    return 0;
}
```

</details>

```
; demo43.c in hlasm: Lisp-style cons cells allocated with GETMAIN and
; returned by pointer; lst->cdr->car->num is three loads.
; Prints "D43OK" and returns 42. Output: "D43OK" then "r0=42".
COPY cor24
COPY frame
COPY svc_bare
COPY check
COPY struct
SET SHOWRC,1

; struct val { int tag; int num; struct val *car; struct val *cdr; };
 DSECT cell
 FIELD v_tag,3
 FIELD v_num,3
 FIELD v_car,3
 FIELD v_cdr,3
 DEND cell

; CONSNUM n: LST = cons(make_num(n), LST)  (a demo-local macro; macros are
; defined before their first use)
MACRO CONSNUM &N
 CALL _make_num,&N
 mov r2,r0
 lw r0,LST(fp)
 CALL _cons,r2,r0
 sw r0,LST(fp)
MEND

 START
_main:
 LOCAL NIL,3
 LOCAL LST,3
 PROLOG
 CHECKINIT
 CALL _make_num,0
 sw r0,NIL(fp)
; lst = cons(make_num(1), cons(make_num(2), cons(make_num(3), nil)))
 lw r0,NIL(fp)
 sw r0,LST(fp)
 CONSNUM 3
 CONSNUM 2
 CONSNUM 1
; lst->car->num == 1, lst->cdr->car->num == 2, lst->cdr->cdr->car->num == 3
 lw r2,LST(fp)
 lw r1,v_car(r2)
 lw r0,v_num(r1)
 CHECK cc_eq,r0,1
 lw r2,v_cdr(r2)
 lw r1,v_car(r2)
 lw r0,v_num(r1)
 CHECK cc_eq,r0,2
 lw r2,v_cdr(r2)
 lw r1,v_car(r2)
 lw r0,v_num(r1)
 CHECK cc_eq,r0,3
; while (p->tag == 1) { sum += p->car->num; p = p->cdr; }
 lc r0,0
 lw r2,LST(fp)
DO
 lw r1,v_tag(r2)
 DOEXIT cc_ne,r1,1
 lw r1,v_car(r2)
 lw r1,v_num(r1)
 add r0,r1
 lw r2,v_cdr(r2)
ENDDO
 CHECK cc_eq,r0,6
 CHECKEND "D43OK\n",42
 RET

; _make_num(n): a new cell with tag 0 and num n
_make_num:
 PROLOG
 GETMAIN r2,SIZEOF_cell
 lc r0,0
 sw r0,v_tag(r2)
 ARG r0,1
 sw r0,v_num(r2)
 RETURN r2

; _cons(a, d): a new cell with tag 1, car a, cdr d
_cons:
 PROLOG
 GETMAIN r2,SIZEOF_cell
 lc r0,1
 sw r0,v_tag(r2)
 ARG r0,1
 sw r0,v_car(r2)
 ARG r0,2
 sw r0,v_cdr(r2)
 RETURN r2
COPY svc_bare_code
```

Output:

```
D43OK
r0=42
```

