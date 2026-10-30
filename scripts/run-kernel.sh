#!/usr/bin/env bash
# run-kernel.sh — assemble a COR24 kernel source and run it in the emulator.
#
#   scripts/run-kernel.sh hlasm.s [cor24-emu options...]
#
# The assembler and the emulator are separate programs (cor24-asm from
# sw-cor24-x-assembler, cor24-emu from sw-cor24-emulator); the old combined
# `cor24-run --run file.s` is gone. This is the one place that joins them:
# every script and regression test in this repository runs hlasm.s through
# here, so `cor24-run --run K OPTS` became `scripts/run-kernel.sh K OPTS`.
#
# The assembled .lgo is a private temporary file, so parallel test runs never
# share one, and it is removed on exit. The emulator's exit status is the
# script's.
#
# cor24-emu stops after 10 s of wall-clock time by default, which a busy
# machine or a parallel test run reaches long before the instruction budget
# (-n) runs out, silently cutting the output short. So unless the caller
# passes -t/--time, this script passes --time ${RUN_KERNEL_TIME:-600}; -n
# remains the real limit.
#
# Tools are found on PATH first. Failing that, COR24_ASM / COR24_EMU name
# them explicitly, then the sibling checkouts' release builds, then the
# binaries vendored by sw-tos.
set -euo pipefail

if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
SIBLINGS="$(cd "$HERE/../.." && pwd)"

find_tool() {
  local name="$1" override="$2"
  shift 2
  if [ -n "$override" ]; then
    echo "$override"
    return
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return
  fi
  local candidate
  for candidate in "$@"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done
  echo "run-kernel: $name not found on PATH; build it, or point COR24_ASM / COR24_EMU at it" >&2
  echo "  looked in: $*" >&2
  exit 1
}

ASM="$(find_tool cor24-asm "${COR24_ASM:-}" \
  "$SIBLINGS/sw-cor24-x-assembler/target/release/cor24-asm" \
  "$SIBLINGS/sw-tos/tools/bin/cor24-asm")"
EMU="$(find_tool cor24-emu "${COR24_EMU:-}" \
  "$SIBLINGS/sw-cor24-emulator/target/release/cor24-emu" \
  "$SIBLINGS/sw-tos/tools/bin/cor24-emu")"

KERNEL="$1"
shift
# A private directory rather than a file: the assembler output needs the .lgo
# extension, and renaming a mktemp file would leave the original behind.
WORK="$(mktemp -d -t run-kernel)"
trap 'rm -rf "$WORK"' EXIT
LGO="$WORK/$(basename "${KERNEL%.s}").lgo"

"$ASM" "$KERNEL" -o "$LGO"
exec_status=0
TIME_ARGS=(--time "${RUN_KERNEL_TIME:-600}")
for arg in "$@"; do
  case "$arg" in
    -t|--time) TIME_ARGS=() ;;
  esac
done
"$EMU" --lgo "$LGO" ${TIME_ARGS[@]+"${TIME_ARGS[@]}"} "$@" || exec_status=$?
exit "$exec_status"
