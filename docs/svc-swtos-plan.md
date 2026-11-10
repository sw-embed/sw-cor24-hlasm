# A sw-tos target for the hlasm services macros (future saga plan)

Status: plan only (2026-11-10). No code yet.

## Goal

HLASM programs written against the services interface (`lib/svc_bare.hlasm`)
should run as sw-tos programs without changing their source. A program picks
its target by which member it COPYs:

```
COPY svc_bare        ; bare metal: UART registers, static heap, bra-to-self halt
COPY svc_swtos       ; sw-tos: kernel services through the glue stubs
```

The macro names, operands and register effects stay the same. Only the
expansions and the code member (`svc_swtos_code`) differ. This was the design
from the start (`docs/limits-and-lifting-plan.md`, "System services plan"). The
bare-metal half shipped with the tiny-C ports in 0.1.0.

## What sw-tos offers (surveyed in ../sw-tos, 2026-11-10)

- **Programs.** sw-tos has no filesystem loader for general programs. A program
  is either:
  - *resident*: linked into the flat kernel image and listed in a catalog
    profile (`catalog/profiles/*.toml`, `[[program]]` with an `entry` symbol,
    `stack_words`, `state_words`, `flags`). The Forth REPL is the model: an
    assembly program (`hal/cor24/forth-swtos.s`) built into the `forth`
    profile.
  - *loaded*: a position-independent C24IMG blob (`catalog/images/*.s` plus a
    `.toml` with the payload). The current blobs are tiny tests that write the
    UART directly; they have no symbol access to kernel services.
- **Kernel services** are entered only through glue stubs named after the
  service (`hal/cor24/glue_generated.s`). The ones the services interface
  needs:

  | Interface | sw-tos service |
  |---|---|
  | `PUTC` | `_UART_PUTCHAR(ch)` |
  | `PUTS`, `WTO` | `_UART_PUTS(str)` |
  | `PUTDEC`, `PUTHEX` | `_TASK_PRINT_UNSIGNED`, `_TASK_PRINT_HEX` (signed decimal needs a '-' and negate first, or stays in library code) |
  | `GETC` | `_TASK_GETCHAR()` |
  | `GETLINE` | a loop over `_TASK_GETCHAR`, or `MSG_TTY_READ_LINE` (2) through `SYS_SENDREC` (5) |
  | `EXIT` | `_TASK_EXIT(code)` |
  | `GETMAIN`/`FREEMAIN` | no allocator service; `_TASK_HEAP_INFO` only reports the loaded-image heap |

- **Calling convention.** PL/SW's is the same as the library's: arguments
  pushed right to left, result in r0, `push fp`/`push r2`/`push r1` prologue,
  first argument at `fp+9`. One difference matters: a glue stub **clobbers r2**
  (`la r2,_SERVICE` / `jal r1,(r2)` is the PL/SW call sequence, and the stub
  uses r2), while the library's `CALL` promises to preserve r2.
- **Preemption.** Code outside the kernel may be preempted anywhere the
  "carpet" covers. A resident program linked after the glue module is inside
  it, so hlasm output needs no special instructions. Its stack is the one the
  catalog gives it (`stack_words`); there is no 3 KB EBR stack of its own.
- **Build.** Multi-module images are assembled with `cor24-asm` and linked with
  `meta-gen` + `link24` (`scripts/catalog-spawn-link.sh`). hlasm's output is
  plain `.s`, so it can join that pipeline as one more module.

## Decisions to make in the first step

1. **Resident only, or loaded too.** Resident programs can call glue stubs by
   name, and the linker resolves them, so start there. Loaded images would
   need relocation records for every service address, or a service table
   passed at entry. Defer that until sw-tos defines one.
2. **Heap.** Give `GETMAIN` a per-program arena:
   - **Option 1:** a `SPACE` block in the program image (simplest, sized by an
     `SVC_HEAP_BYTES` symbol).
   - **Option 2:** the catalog's `state_words`.

   Ask sw-tos for an allocator service only if a real program needs one.
3. **r2 across services.** Either the `svc_swtos` macros save and restore r2
   around each stub call (one `push`/`pop` pair, so programs keep the
   library's promise), or the interface documents r2 as clobbered for
   services on every target. The first keeps programs portable, so prefer it.
4. **Program entry and exit.** `START` becomes the catalog entry symbol, and
   `EXITCODE` calls `_TASK_EXIT`. `SHOWRC` keeps printing `r0=<n>` through
   `_UART_PUTS` so the same regression output works on both targets.
5. **Where the glue symbols come from.** Use a small `lib/swtos.hlasm` with the
   service names as comments, or nothing at all, since the linker resolves
   names that hlasm passes through unchanged. Pin the sw-tos commit the
   member was checked against.

## Phases (proposed saga steps)

1. **Decide and stub.** Write `lib/svc_swtos.hlasm` and
   `lib/svc_swtos_code.hlasm` for the decisions above: console, `EXIT`,
   `START`, the arena `GETMAIN`. Every macro of `svc_bare` must exist with the
   same operands, even where its sw-tos expansion is simple.
2. **Build path.** Add a script in this repo or in sw-tos (to be agreed with
   that repo) that runs hlasm on a source set and adds the `.s` as a module to
   a sw-tos profile. Then link a `hlasm-hello` profile with
   `catalog-spawn-link.sh` and run it in `cor24-emu`.
3. **Same programs, both targets.** Build a few `demos/tinyc` ports against
   `svc_swtos` by changing only their source set: hello, demo13, demo41
   (strings and atoi), demo43 (heap). Give each an e2e test whose output
   matches the bare-metal baseline, apart from sw-tos's own banner, which the
   test filters out.
4. **Input.** Add `GETC`/`GETLINE` on `_TASK_GETCHAR` (or `MSG_TTY_READ_LINE`)
   with a scripted TTY input test.
5. **Buffer I/O and framing** (`DCB`, `OPEN`/`GET`/`PUT`, `UFRAME_*`) only
   when a consumer exists: plsw or hlasm self-hosting under sw-tos.

## Dependencies and risks

- sw-tos's link pipeline is Python-driven (`generate-catalog.py`, `meta-gen`).
  This repo's own code stays shell and `.s`, so the integration script either
  lives in sw-tos or only calls those tools.
- Glue stubs are generated from kernel exports, so service names and
  signatures can change. Pin a sw-tos commit and add a check that each name
  `svc_swtos` uses still exists.
- Resident programs share one address space. The arena must not overlap
  another program's state, so take it from the program's own image or state
  words, never from a fixed address like `svc_bare`'s 0x080000.
