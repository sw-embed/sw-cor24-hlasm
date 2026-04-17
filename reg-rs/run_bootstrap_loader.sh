#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <loader.hlasm> <max-instructions>"
    exit 1
fi

SPEC="$1"
MAX_INSNS="$2"
shift 2

if [[ ! -f "$SPEC" ]]; then
    echo "ERROR: $SPEC not found"
    exit 1
fi

cfg_txt="/tmp/sw-cor24-hlasm-loader-$$.cfg.txt"
cfg_bin="/tmp/sw-cor24-hlasm-loader-$$.cfg"

load_args=()
extra_count=0

: > "$cfg_txt"

while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%;*}"
    line="${line%%#*}"
    line="${line//,/ }"

    set -- $line

    if [[ $# -eq 0 ]]; then
        continue
    fi

    case "$1" in
        MAIN)
            if [[ $# -ne 2 ]]; then
                echo "ERROR: MAIN expects: MAIN <file.bin>@<addr>"
                exit 1
            fi

            file_part="${2%@*}"
            addr_part="${2#*@}"

            if [[ ! -f "$file_part" ]]; then
                echo "ERROR: $file_part not found"
                exit 1
            fi

            size_part="$(wc -c < "$file_part")"
            printf 'main %s %s\n' "$addr_part" "$size_part" >> "$cfg_txt"
            load_args+=("--load-binary" "${file_part}@${addr_part}")
            ;;
        SRCBUF)
            if [[ $# -ne 3 ]]; then
                echo "ERROR: SRCBUF expects: SRCBUF <slot> <file.bin>@<addr>"
                exit 1
            fi

            extra_count=$(( extra_count + 1 ))
            if [[ "$2" -ne "$extra_count" ]]; then
                echo "ERROR: SRCBUF slots must be declared in order starting at 1"
                exit 1
            fi

            file_part="${3%@*}"
            addr_part="${3#*@}"

            if [[ ! -f "$file_part" ]]; then
                echo "ERROR: $file_part not found"
                exit 1
            fi

            size_part="$(wc -c < "$file_part")"
            printf 'extra %s %s\n' "$addr_part" "$size_part" >> "$cfg_txt"
            load_args+=("--load-binary" "${file_part}@${addr_part}")
            ;;
        INCLUDE)
            if [[ $# -ne 3 ]]; then
                echo "ERROR: INCLUDE expects: INCLUDE <name> <slot>"
                exit 1
            fi

            printf 'include %s %s\n' "$3" "$2" >> "$cfg_txt"
            ;;
        *)
            echo "ERROR: unknown loader directive '$1'"
            exit 1
            ;;
    esac
done < "$SPEC"

bash reg-rs/make_cfg.sh "$cfg_txt" "$cfg_bin"

exec cor24-run --run hlasm.s \
    "${load_args[@]}" \
    --load-binary "${cfg_bin}@520192" \
    --stack-kilobytes 3 \
    --speed 0 \
    -n "$MAX_INSNS" \
    "$@"
