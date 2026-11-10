#!/usr/bin/env bash
# c-demos.sh [--table] -- the tiny-C demos ported to hlasm (demos/tinyc/).
#
#   scripts/c-demos.sh          run every port end to end and compare its
#                               output with the regression baseline
#                               (reg-rs/hlasm_e2e_tinyc_<demo>.out)
#   scripts/c-demos.sh --table  print a markdown table comparing each port
#                               with tc24r's compiled version: source lines,
#                               generated instruction lines, code bytes and
#                               instructions executed
#
# The table needs the tiny-C checkout (TINYC_DEMOS, default
# ../sw-cor24-x-tinyc/demos) for the C sources and tc24r's .s files. The hlasm
# side is measured without the "r0=" report (SET SHOWRC,1 is dropped), so
# both versions do the same work. See docs/c-demos-in-hlasm.md.
set -euo pipefail
cd "$(dirname "$0")/.."

TINYC="${TINYC_DEMOS:-../sw-cor24-x-tinyc/demos}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/c-demos.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

demos=()
for f in demos/tinyc/*.sourceset; do
  demos+=("$(basename "${f%.sourceset}")")
done

# emu_args <demo>: what the program run needs (as in check_tinyc.sh)
emu_args() {
  case "$1" in
    demo9) echo "-u A" ;;
    *) echo "" ;;
  esac
}

if [ "${1:-}" != "--table" ]; then
  pass=0
  fail=0
  for d in "${demos[@]}"; do
    if bash reg-rs/check_tinyc.sh "$d" > "$WORK/$d.out" 2>&1 \
      && cmp -s "$WORK/$d.out" "reg-rs/hlasm_e2e_tinyc_$d.out"; then
      pass=$((pass + 1))
      printf 'ok    %-14s %s\n' "$d" "$(tr '\n' ' ' < "$WORK/$d.out")"
    else
      fail=$((fail + 1))
      printf 'FAIL  %-14s %s\n' "$d" "$(tr '\n' ' ' < "$WORK/$d.out")"
    fi
  done
  echo "$pass ported demos match their baselines, $fail differ"
  [ "$fail" -eq 0 ]
  exit
fi

ASM="${COR24_ASM:-$(command -v cor24-asm || echo ../sw-cor24-x-assembler/target/release/cor24-asm)}"

# code_lines <file.s>: lines that are instructions or data, not labels,
# comments, blank lines or .globl/.text/.data
code_lines() {
  grep -v -E '^[[:space:]]*($|;)' "$1" | grep -v -E '^[A-Za-z_.][A-Za-z0-9_.]*:[[:space:]]*$' \
    | grep -v -E '^[[:space:]]*\.(globl|text|data)' | grep -c . || true
}

# src_lines <file>: non-blank lines that are not comments (// or ;)
src_lines() {
  grep -v -E '^[[:space:]]*($|//|;|\*|/\*)' "$1" | grep -c . || true
}

# measure <file.s> <demo>: "bytes executed" of the assembled program
measure() {
  local bytes executed
  "$ASM" "$1" --bin "$WORK/m.bin" > /dev/null 2>&1
  bytes=$(wc -c < "$WORK/m.bin" | tr -d ' ')
  # shellcheck disable=SC2046
  executed=$(scripts/run-kernel.sh "$1" --speed 0 -n 5000000 -q $(emu_args "$2") 2>&1 >/dev/null \
    | sed -n 's/^Executed \([0-9]*\) instructions.*/\1/p' | tail -1)
  echo "$bytes ${executed:-?}"
}

echo "| Demo | C lines | HLASM lines | tc24r .s lines | hlasm .s lines | tc24r bytes | hlasm bytes | tc24r executed | hlasm executed |"
echo "|---|---:|---:|---:|---:|---:|---:|---:|---:|"
for d in "${demos[@]}"; do
  base="${d%_andor}"
  csrc="$TINYC/$base.c"
  hsrc="demos/tinyc/$d.hlasm"
  [ -f "$csrc" ] || continue
  # hlasm version without the r0 report
  grep -v '^SET SHOWRC,1$' "$hsrc" > "$WORK/main.hlasm"
  {
    printf 'ROOT %s\n' "$PWD/demos/tinyc"
    printf 'MAIN %s\n' "$WORK/main.hlasm"
    grep '^COPY ' "demos/tinyc/$d.sourceset" || true
    printf 'SOURCESET %s\n' "$PWD/lib/lib.sourceset"
  } > "$WORK/main.sourceset"
  # shellcheck disable=SC2046
  scripts/hlasm-e2e.sh --keep-s "$WORK/h.s" "$WORK/main.sourceset" -- $(emu_args "$d") > /dev/null 2>&1 || true
  read -r hb hx <<< "$(measure "$WORK/h.s" "$d")"
  hl=$(code_lines "$WORK/h.s")
  if [ -f "$TINYC/$base.s" ]; then
    read -r tb tx <<< "$(measure "$TINYC/$base.s" "$d")"
    tl=$(code_lines "$TINYC/$base.s")
  else
    tb="-" tx="-" tl="-"
  fi
  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' "$d" \
    "$(src_lines "$csrc")" "$(src_lines "$hsrc")" "$tl" "$hl" "$tb" "$hb" "$tx" "$hx"
done
