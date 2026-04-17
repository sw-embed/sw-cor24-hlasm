#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <input.hlasm> <output.bin>"
    exit 1
fi

SRC="$1"
OUT="$2"

if [[ ! -f "$SRC" ]]; then
    echo "ERROR: $SRC not found"
    exit 1
fi

printf '%s' "$(<"$SRC")" > "$OUT"
echo "Created $OUT ($(wc -c < "$OUT") bytes)"
