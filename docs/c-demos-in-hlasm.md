# The tiny-C demos in hlasm

The C compiler tc24r (`../sw-cor24-x-tinyc`) ships about seventy small
demo programs. This document shows those programs rewritten in hlasm,
side by side with the C, using a shared macro library. The point is to
show what macros buy over writing plain COR24 assembly, and how close
hlasm source can come to the C it replaces.

Status: **planned.** No demo has been ported yet. This page lists the
macros that were chosen and the order of the ports. Each port step adds
its demos below. The detailed survey and reasoning are in
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

The library is a set of COPY members under `lib/`. Macros-only members
can be COPYed anywhere, because they produce no code until a macro is
called. Code members (the runtime routines) are COPYed at the end of the
program, and they emit only the routines the program actually called.

The routines follow tc24r's calling convention, so hlasm code and
tc24r-compiled code can call each other:

- arguments are pushed right to left, and the caller pops them;
- the result comes back in r0;
- the prologue is `push fp`/`push r2`/`push r1`, and the first argument is
  at `9(fp)`.

| Member | Macros |
|---|---|
| `lib/cor24.hlasm` | board addresses as `EQU`s: `UART_DATA`, `UART_STATUS`, `LED_REG`, `INT_ENABLE`, `LED_ON`, `LED_OFF` |
| `lib/frame.hlasm` | `PROLOG [locals]`, `RET`, `RETURN value`, `ARG reg,n`, `LOCAL name,bytes`, `CALL fn,args...`, `START` |
| `lib/svc_bare.hlasm` | console and storage: `PUTC`, `PUTS`, `PUTDEC`, `PUTHEX`, `PUTNL`, `WTO "text"`, `GETC`, `GETLINE`, `GETMAIN`, `FREEMAIN`, `EXIT` |
| `lib/board.hlasm` | `LEDON`, `LEDOFF`, `BUTTON reg` |
| `lib/data.hlasm` | `STR label,"text"`, `WORDS`, `BYTES`, `SPACE` |
| `lib/check.hlasm` | `CHECKINIT`, `CHECK cond,a,b`, `CHECKEND 'DnOK',rc`: the demos' self-test pattern |
| `lib/rt.hlasm`, `lib/svc_bare_rt.hlasm` | routines: decimal and hex printing, divide and modulo, `strlen`, `strcmp`, `strcpy`, `memcpy`, `memset`, `atoi`, and the allocator |

`svc_bare.hlasm` is the bare-metal version of the services interface
(console, storage and later buffer I/O). A sw-tos version with the same
macro names can replace it without changing the programs.

To give a feel for the result, this is `hello.c`:

```c
void putc(int c) { while (*(char *)0xFF0101 & 0x80) {} *(char *)0xFF0100 = c; }
void puts(char *s) { while (*s) { putc(*s); s = s + 1; } }
int main() { puts("Hello, COR24!\n"); return 0; }
```

tc24r compiles it to 96 lines of assembly. The planned hlasm port is
about this size:

```
 START
_main:
 PROLOG
 WTO "Hello, COR24!\n"
 RETURN 0
```

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
