#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="${1:-$ROOT/hlasm.s}"

if [[ ! -f "$FILE" ]]; then
    echo "ERROR: $FILE not found" >&2
    exit 1
fi

labels=()
while IFS= read -r line; do
    labels+=("$line")
done < <(rg -n '^_[A-Za-z0-9_]+:' "$FILE")

functions=()
for entry in "${labels[@]}"; do
    line_no="${entry%%:*}"
    probe="$(sed -n "${line_no},$((line_no + 5))p" "$FILE")"
    if grep -q $'^\tpush\tfp$' <<<"$probe"; then
        functions+=("$entry")
    fi
done

status=0
for ((i = 0; i < ${#functions[@]}; i++)); do
    entry="${functions[$i]}"
    line_no="${entry%%:*}"
    label="${entry#*:}"

    if (( i + 1 < ${#functions[@]} )); then
        next_line="${functions[$((i + 1))]%%:*}"
        count=$((next_line - line_no - 1))
    else
        count=100000
    fi

    body="$( (tail -n +"$line_no" "$FILE" | head -n "$count") || true )"
    code_only="$(grep -Ev '^(;|[[:space:]]*$)' <<<"$body" || true)"

    uses_r2=0
    saves_r2=0
    restores_r2=0

    if grep -Eq '(^|[^[:alnum:]_])r2([^[:alnum:]_]|$)' <<<"$code_only"; then
        uses_r2=1
    fi
    if grep -q $'^\tpush\tr2$' <<<"$code_only"; then
        saves_r2=1
    fi
    if grep -q $'^\tpop\tr2$' <<<"$code_only"; then
        restores_r2=1
    fi

    if (( uses_r2 == 1 )) && (( saves_r2 == 0 || restores_r2 == 0 )); then
        echo "SUSPECT ${label%:} line ${line_no}: uses r2 without full callee-save prologue/epilogue"
        status=1
    fi
done

exit "$status"
