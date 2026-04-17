#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <input.cfg.txt> <output.cfg>"
    exit 1
fi

SRC="$1"
OUT="$2"

if [[ ! -f "$SRC" ]]; then
    echo "ERROR: $SRC not found"
    exit 1
fi

emit_byte() {
    local value="$1"
    printf '%b' "\\x$(printf '%02x' "$value")"
}

emit_word24() {
    local value="$1"
    emit_byte $(( value        & 255 ))
    emit_byte $(( (value >> 8) & 255 ))
    emit_byte $(( (value >> 16) & 255 ))
}

emit_name9() {
    local name="$1"
    local len=${#name}
    local i=0

    if (( len > 8 )); then
        echo "ERROR: include name '$name' exceeds 8 characters"
        exit 1
    fi

    while (( i < len )); do
        printf '%s' "${name:i:1}"
        i=$(( i + 1 ))
    done

    while (( i < 9 )); do
        emit_byte 0
        i=$(( i + 1 ))
    done
}

main_base=0
main_len=0

extra_count=0
extra1_base=0
extra1_len=0
extra2_base=0
extra2_len=0
extra3_base=0
extra3_len=0

include_count=0
include_slots=()
include_names=()

while IFS= read -r line || [[ -n "$line" ]]; do
    set -- $line

    if [[ $# -eq 0 ]]; then
        continue
    fi

    if [[ "$1" == "#" ]]; then
        continue
    fi

    case "$1" in
        main)
            if [[ $# -ne 3 ]]; then
                echo "ERROR: main expects: main <base> <len>"
                exit 1
            fi
            main_base="$2"
            main_len="$3"
            ;;
        extra)
            if [[ $# -ne 3 ]]; then
                echo "ERROR: extra expects: extra <base> <len>"
                exit 1
            fi

            extra_count=$(( extra_count + 1 ))
            if (( extra_count > 3 )); then
                echo "ERROR: config supports at most 3 extra buffers"
                exit 1
            fi

            case "$extra_count" in
                1)
                    extra1_base="$2"
                    extra1_len="$3"
                    ;;
                2)
                    extra2_base="$2"
                    extra2_len="$3"
                    ;;
                3)
                    extra3_base="$2"
                    extra3_len="$3"
                    ;;
            esac
            ;;
        include)
            if [[ $# -ne 3 ]]; then
                echo "ERROR: include expects: include <slot> <name>"
                exit 1
            fi

            include_slots+=("$2")
            include_names+=("$3")
            include_count=$(( include_count + 1 ))
            ;;
        *)
            echo "ERROR: unknown directive '$1'"
            exit 1
            ;;
    esac
done < "$SRC"

{
    emit_word24 "$extra_count"

    emit_word24 "$extra1_base"
    emit_word24 "$extra1_len"
    emit_word24 "$extra2_base"
    emit_word24 "$extra2_len"
    emit_word24 "$extra3_base"
    emit_word24 "$extra3_len"

    emit_word24 "$main_base"
    emit_word24 "$main_len"

    emit_word24 "$include_count"

    i=0
    while (( i < include_count )); do
        emit_word24 "${include_slots[$i]}"
        emit_name9 "${include_names[$i]}"
        i=$(( i + 1 ))
    done
} > "$OUT"
