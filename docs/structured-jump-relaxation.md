# Structured Jump Relaxation (design)

Status: designed, not yet implemented.

## Problem

Structured lowering (`IF`/`ELSEIF`/`ELSE`, `DO`/`DOEXIT`/`ITERATE`,
`SELECT`/`WHEN`/`OTHERWISE`) emits `jmp <label>`, e.g.

```
 brt _hlif_3_skip
 jmp _hlif_1_false
_hlif_3_skip:
```

COR24 `jmp` is register-indirect only (`jmp (r0)`); `cor24-asm` rejects
`jmp <label>` ("Invalid jmp syntax") and always has. reg-rs compares hlasm's
text output and never assembles it, so this went unnoticed. Affected demos:
d11, d12, d13, d26, d29, d30, d32, d35, d36. The emitters are the 13
`la r0,_jmp_txt` sites, which call `_emit_branch_label`,
`_emit_do_branch_label` or `_emit_select_branch_label` (prefixes
`_hlif_`, `_hldo_`, `_hlsel_`).

## Decided lowering

Use `bra` when the target is in range; otherwise save r2 around `la`/`jmp`:

- near: ` bra L`
- far:  ` push r2` / ` la r2,L_far` / ` jmp (r2)`

A far target label gets a trampoline so r2 is restored at the destination
(a pop cannot follow a jmp):

```
 bra L          ; fallthrough skips the pop
L_far:
 pop r2
L:
```

The existing `brt skip` / `<jump>` / `skip:` shape stays; only the `jmp`
line changes. (Folding to a single inverted conditional branch is a later
optimisation.)

## Range

From sw-cor24-isa: `bra`/`brt`/`brf` are 2 bytes with a signed 8-bit offset
relative to `branch_address + 4`; offset must be in `[-128, 127]`. No
instruction exceeds 4 bytes.

## Two passes

hlasm streams output, so a forward target's distance is unknown when the
jump is emitted. hlasm keeps all source in memory, so it can run twice:

1. **Pass 1** (output suppressed): `_emit_char` feeds a line sizer instead
   of the UART. Record each structured label's position (by label id) and
   each relaxed jump's position and target id (by jump sequence number).
   At end of pass 1, mark jump k far if
   `label_pos[tgt] - (jump_pos[k] + 4)` is outside `[-128, 127]`, and mark
   its target label as needing a trampoline.
2. **Pass 2**: restore pristine state, rerun, emit for real using the far
   flags. Jump sequence numbers and label ids replay identically.

### Why one sizing pass is enough

Pass 1 counts an upper bound for every line, emits the far form for every
relaxed jump, and emits a trampoline for every label definition. Pass 2
lines are never larger, so every span between two points only shrinks.
For a forward jump the offset can only fall (and stays >= -4); for a
backward jump it can only rise toward zero. A jump that fits in pass 1
fits in pass 2. No iteration is needed.

### Line sizer (pass 1, on each completed output line)

- skip a leading `name:` label (also allows `label: insn` on one line)
- empty or `;` comment: 0
- `.byte a,b,...`: commas + 1; `.word ...`: 3 * (commas + 1)
- any `"` on a `.byte` line, or any other directive: poison (add 0x8000),
  forcing every jump spanning it far. `.text`/`.data`/`.globl` count 0.
- anything else is an instruction: 4

### State restore between passes

Mutable state lives in the program image (data clusters near hlasm.s lines
3959-4067 and 10677-end, plus small ones near 1485-1640) and in the runtime
arena at 0x0C0000 (re-initialised by `_init_runtime_arena`). On pass-1
entry, copy the image's mutable data to a save area; before pass 2, copy it
back and re-enter `_main`. The pass flag lives in the image (loader
initialises it to 0) and is set to 1 after the restore. Copying the whole
image (code is never self-modified) is simplest but costs instructions;
prefer copying only the data clusters (add `_data_*_begin/_end` labels).

### Memory

- 0x0D0000: image/data snapshot
- 0x0E0000: relax state: pass-1 position counter, line buffer (256),
  label_pos[2048] (3 bytes each), jump_pos[2048], jump_tgt[2048],
  jump_far[2048] (1 byte), label_far[2048] (1 byte), jump counter.
  Ids or sequence numbers >= 2048: jump is always far, and the label always
  gets a trampoline (consistent, always correct).

## Test impact

- Every baseline's `Executed N instructions` changes (two passes); several
  `-n` budgets must rise.
- Pass-2 UART output must equal the old output except the `jmp` lines and
  the added trampolines; verify that per test before rebasing.
- Add an end-to-end check: feed each structured demo's output to `cor24-asm`
  and require success (the gap that hid this bug).
