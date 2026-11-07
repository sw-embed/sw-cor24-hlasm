#!/usr/bin/env bash
# hlasm-e2e.sh — run a .hlasm program end to end and print its UART output.
#
#   scripts/hlasm-e2e.sh [options] <file.hlasm | file.sourceset> [-- emu-args...]
#
# Stages: hlasm.s runs on cor24-emu and turns the source into plain COR24
# assembly; cor24-asm assembles that; cor24-emu runs the result. Only the
# program's UART output reaches stdout. A .sourceset input (MAIN plus
# INCLUDE/COPY members) goes through reg-rs/run_bootstrap_sourceset.sh.
#
# Options:
#   --hlasm-n N   instruction budget for the hlasm run (default 200000000)
#   --run-n N     instruction budget for the program run (default 1000000)
#   --keep-s F    also write the generated assembly to F
# Arguments after -- go to the program's cor24-emu (e.g. -u, --switch).
#
# Exit status: 0 ok, 1 usage or missing input, 2 hlasm failed (ERROR: line
# or budget used up), 3 cor24-asm rejected the output, 4 the program did not
# halt within --run-n or cor24-emu failed. Diagnostics go to stderr.
set -euo pipefail

usage() {
  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 1
}

die() {
  local code="$1"
  shift
  echo "hlasm-e2e: $*" >&2
  exit "$code"
}

HLASM_N=200000000
RUN_N=1000000
KEEP_S=""
SRC=""
EMU_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    --hlasm-n) [ $# -ge 2 ] || usage; HLASM_N="$2"; shift 2 ;;
    --run-n) [ $# -ge 2 ] || usage; RUN_N="$2"; shift 2 ;;
    --keep-s) [ $# -ge 2 ] || usage; KEEP_S="$2"; shift 2 ;;
    --) shift; EMU_ARGS=("$@"); break ;;
    -*) usage ;;
    *) [ -z "$SRC" ] || usage; SRC="$1"; shift ;;
  esac
done

[ -n "$SRC" ] || usage
[ -f "$SRC" ] || die 1 "$SRC not found"

# Absolute paths first: the stages run from the repository root.
SRC="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
case "$KEEP_S" in
  ""|/*) ;;
  *) KEEP_S="$(pwd)/$KEEP_S" ;;
esac
cd "$(dirname "$0")/.."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hlasm-e2e.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
OUT_S="$WORK/out.s"

# executed <log>: the instruction count from cor24-emu's summary line.
executed() {
  sed -n 's/^Executed \([0-9]*\) instructions.*/\1/p' "$1" | tail -1
}

# Stage 1: hlasm.
status=0
case "$SRC" in
  *.sourceset)
    bash reg-rs/run_bootstrap_sourceset.sh "$SRC" "$HLASM_N" -q \
      > "$OUT_S" 2> "$WORK/hlasm.log" || status=$?
    ;;
  *)
    bash demos/make_bin.sh "$SRC" "$WORK/src.bin" > /dev/null
    scripts/run-kernel.sh hlasm.s --load-binary "$WORK/src.bin@524288" \
      --speed 0 -n "$HLASM_N" -q > "$OUT_S" 2> "$WORK/hlasm.log" || status=$?
    ;;
esac
[ -z "$KEEP_S" ] || cp "$OUT_S" "$KEEP_S"
if [ "$status" -ne 0 ]; then
  cat "$OUT_S" "$WORK/hlasm.log" >&2
  die 2 "hlasm run failed (status $status)"
fi
if grep -q '^ERROR:' "$OUT_S"; then
  grep '^ERROR:' "$OUT_S" >&2
  die 2 "hlasm reported an error"
fi
if [ "$(executed "$WORK/hlasm.log")" = "$HLASM_N" ]; then
  die 2 "hlasm used its whole budget of $HLASM_N instructions (raise --hlasm-n)"
fi

# Stages 2 and 3: run-kernel.sh assembles with cor24-asm, then runs.
status=0
scripts/run-kernel.sh "$OUT_S" --speed 0 -n "$RUN_N" -q \
  ${EMU_ARGS[@]+"${EMU_ARGS[@]}"} > "$WORK/uart.txt" 2> "$WORK/run.log" \
  || status=$?
if ! grep -q '^Executed ' "$WORK/run.log"; then
  cat "$WORK/run.log" >&2
  die 3 "cor24-asm rejected the generated assembly (status $status)"
fi
cat "$WORK/uart.txt"
if [ "$status" -ne 0 ]; then
  cat "$WORK/run.log" >&2
  die 4 "cor24-emu failed (status $status)"
fi
if [ "$(executed "$WORK/run.log")" = "$RUN_N" ]; then
  die 4 "program did not halt within $RUN_N instructions (raise --run-n)"
fi
