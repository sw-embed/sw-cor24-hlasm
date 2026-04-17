# RPG-II Blocker Note

This repo was checked in response to a reported `../sw-cor24-rpg-ii` blocker.
The important result is:

- `hlasm.s` does **not** truncate `rpg2.hlasm` mid-file when given enough
  instruction budget.
- The apparent truncation is caused by the dependent build using a stage-0
  limit that is too low for the current `rpg2.hlasm` size.

## Reproduction

From this repo root:

```bash
timeout 8 cor24-run --run ../sw-cor24-hlasm/hlasm.s \
  --load-binary ../sw-cor24-rpg-ii/rpg2.hlasm@524288 \
  --speed 0 -n 2000000 2>&1
```

With `-n 2000000`, UART output stops in `_parse_i_spec` and the generated file
looks truncated.

With a larger budget:

```bash
cor24-run --run hlasm.s \
  --load-binary ../sw-cor24-rpg-ii/rpg2.hlasm@524288 \
  --speed 0 -n 12000000 2>&1
```

stage-0 completes successfully. Measured on this machine:

- full generated source length: `1083` lines
- stage-0 instruction count: `4172271`
- generated tail reaches `_indicator_table:`

## Downstream Change Needed In `sw-cor24-rpg-ii`

The `rpg-ii` repo should change its `build.sh` generation step from:

```bash
--speed 0 -n 2000000
```

to something comfortably above the measured requirement, for example:

```bash
--speed 0 -n 12000000
```

It should also reject incomplete generated files explicitly, for example by
checking that the generated source reaches a known tail label such as:

```bash
^_indicator_table:$
```

That avoids treating a partial stage-0 output file as valid input to the next
assembler pass.

## What Happens After The Truncation Is Removed

Once stage-0 is allowed to finish, the dependent build no longer fails with
undefined labels from a half-generated file. The next real issues become
visible during the second-stage assemble:

- `Invalid mul operands`
- `Branch target '_src_parse_fail' too far`

Those are separate downstream source/backend issues in `sw-cor24-rpg-ii`. They
are not evidence of another mid-file `hlasm` truncation bug.

## Verification Residue

During verification, the sibling repo `../sw-cor24-rpg-ii` was run and now may
contain untracked `build/` artifacts from that run. No intentional source edits
should remain there; any future agent working in that repo should either ignore
or clean the generated `build/` directory before proceeding.
