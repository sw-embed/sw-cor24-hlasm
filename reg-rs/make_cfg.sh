#!/usr/bin/env bash
set -euo pipefail

# make_cfg.sh <input.cfg.txt> <output.cfg>
#
# Builds the hlasm source config block (loaded at 0x07F000). Input lines:
#   main <base> <len>        override the main source buffer (0 = default)
#   mainname <name>          main source name used in ERROR locations
#   extra <base> <len>       add a member buffer (slots 1-32, in order)
#   include <slot> <name>    name member <slot> for INCLUDE/COPY
#   # ...                    comment
# Names are at most 15 characters.
#
# Output layout (24-bit little-endian words):
#   +0   member count N (0-32)
#   +3   main base override (0 = default 0x080000)
#   +6   main length override (0 = default 32767)
#   +9   main name: 16 bytes, NUL-terminated
#   +25  N member records of 22 bytes: base, length, name (16 bytes)

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

MAX_MEMBERS=32

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

check_name() {
    if (( ${#1} > 15 )); then
        echo "ERROR: name '$1' exceeds 15 characters"
        exit 1
    fi
}

emit_name16() {
    local name="$1"
    local len=${#name}
    local i=0

    while (( i < len )); do
        printf '%s' "${name:i:1}"
        i=$(( i + 1 ))
    done

    while (( i < 16 )); do
        emit_byte 0
        i=$(( i + 1 ))
    done
}

main_base=0
main_len=0
main_name=""

extra_count=0
extra_bases=()
extra_lens=()
extra_names=()

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
        mainname)
            if [[ $# -ne 2 ]]; then
                echo "ERROR: mainname expects: mainname <name>"
                exit 1
            fi
            check_name "$2"
            main_name="$2"
            ;;
        extra)
            if [[ $# -ne 3 ]]; then
                echo "ERROR: extra expects: extra <base> <len>"
                exit 1
            fi

            extra_count=$(( extra_count + 1 ))
            if (( extra_count > MAX_MEMBERS )); then
                echo "ERROR: config supports at most $MAX_MEMBERS member buffers"
                exit 1
            fi
            extra_bases+=("$2")
            extra_lens+=("$3")
            extra_names+=("")
            ;;
        include)
            if [[ $# -ne 3 ]]; then
                echo "ERROR: include expects: include <slot> <name>"
                exit 1
            fi
            check_name "$3"
            if (( $2 < 1 || $2 > extra_count )); then
                echo "ERROR: include slot $2 is not a defined extra buffer"
                exit 1
            fi
            if [[ -n "${extra_names[$(( $2 - 1 ))]}" ]]; then
                echo "ERROR: slot $2 is already named '${extra_names[$(( $2 - 1 ))]}'"
                exit 1
            fi
            extra_names[$(( $2 - 1 ))]="$3"
            ;;
        *)
            echo "ERROR: unknown directive '$1'"
            exit 1
            ;;
    esac
done < "$SRC"

{
    emit_word24 "$extra_count"
    emit_word24 "$main_base"
    emit_word24 "$main_len"
    emit_name16 "$main_name"

    i=0
    while (( i < extra_count )); do
        emit_word24 "${extra_bases[$i]}"
        emit_word24 "${extra_lens[$i]}"
        emit_name16 "${extra_names[$i]}"
        i=$(( i + 1 ))
    done
} > "$OUT"
