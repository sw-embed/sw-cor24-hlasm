# Structured Jump Relaxation (design)

Status: implemented (tinyc-macro-ports saga, step 1).

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
relaxed jump, and emits a trampoline before every non-`_skip` structured
label (`_skip` labels are only ever targets of short `brt`/`brf`, never of
a structured jump). Pass 2 lines are never larger, so every span between
two points only shrinks. For a forward jump the offset can only fall (and
stays >= -4); for a backward jump it can only rise toward zero. A jump that
fits in pass 1 fits in pass 2. No iteration is needed.

### Line sizer (pass 1, on each completed output line)

- skip a leading `name:` label (also allows `label: insn` on one line)
- empty or `;` comment: 0
- `.byte a,b,...`: commas + 1; `.word ...`: 3 * (commas + 1)
- a quote (`"` or `'`) on a `.byte`/`.word` line, any other directive, or a
  line over 255 characters: 256, forcing every jump spanning it far.
  `.text`/`.data`/`.glob*` count 0.
- anything else is an instruction: 4

## Implementation (hlasm.s)

- `_main` calls `_relax_begin_pass` first. When `_relax_pass` is 0 it saves
  the mutable data and clears the flag tables. At the end of pass 1 `_main`
  calls `_relax_end_pass1` (resolve far jumps, restore the data, set
  `_relax_pass` to 1) and re-enters itself; after pass 2 it halts.
- `_emit_char` sends bytes to `_relax_size_char` in pass 1 and to the UART
  in pass 2.
- `_emit_branch_label`, `_emit_do_branch_label` and
  `_emit_select_branch_label` hand `jmp` requests to `_emit_relaxed_jump`;
  the matching `*_label_def` emitters call `_relax_label_def` first.
- `_relax_resolve` marks jump k far, and its target as needing a
  trampoline, when the target is undefined or
  `label_pos[tgt] - jump_pos[k] - 4` is outside `[-128, 127]`.

### State restore between passes

Mutable state lives in two data regions of the image (`_const_A` up to
`_line_is_keyword`, and `_id_buf` up to `_image_end`, which must stay the
last label in hlasm.s) and in the runtime arena at 0x0C0000, which
`_init_runtime_arena` re-initialises on each pass. `_relax_snapshot` copies
the two regions to 0x0D0000 at pass-1 start and back before pass 2. The
pass flag `_relax_pass` lives in the second region: the loader initialises
it to 0, the restore puts it back to 0, and it is then set to 1.

### Memory

- 0x0D0000 (851968): data snapshot (region 1 at +0, region 2 at +1024;
  `_main` stops with an ERROR if region 1 outgrows its 1 KB slot)
- 0x0E0000 (917504): relax state: +0 position, +3 jump count, +6 line
  length, +16 line buffer (256 bytes); label_pos[4096] at 921600,
  jump_pos[4096] at 933888, jump_tgt[4096] at 946176 (3 bytes each);
  label_def[4096] at 958464, label_far[4096] at 962560, jump_far[4096] at
  966656 (1 byte each). (These were 1024 entries until step 4.)
- Label ids or jump numbers >= 4096: the jump is always far, and a
  non-`_skip` label with such an id always gets a trampoline (consistent,
  always correct).

## Cost and tests

- Two passes cost about 2-3x the instructions of one, plus ~30K fixed.
  reg-rs budgets were raised to 3x + 100K; bootstrap defaults to 460000.
- Pass-2 output was checked per test against the old baselines: identical
  except `jmp L` -> `bra L` (no existing demo needed the far form).
- d40 (`demos/d40_long_range_jumps.hlasm`) forces the far form and the
  trampoline; `hlasm_d40_long_range_run` assembles and runs its output.
- `reg-rs/check_structured_asm.sh` (test `hlasm_structured_asm_check`)
  assembles every structured demo's output; all of them report `ok`.

## Issues found while testing (fixed in step 3)

- DOEXIT exited when its condition was false, the opposite of
  docs/design.md. It now exits when true, and d40 prints `32`.
- Compares with `r2` on the left emitted the unencodable `ceq r2,r1`;
  `ceq` operands are now put in ascending register order.
- `0b` literals reached `lc` unconverted; they are now emitted in decimal.
- Several demos used instructions COR24 cannot encode (`sub r0,r0`,
  `xor r0,r0`, `shl r0,1`) or an undefined label (`_body`); they were
  rewritten.

See D1-D3 and D7 in docs/limits-and-lifting-plan.md.
