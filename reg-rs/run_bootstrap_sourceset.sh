#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <sourceset.txt> <max-instructions>"
    exit 1
fi

SRCSET="$1"
MAX_INSNS="$2"
shift 2

if [[ ! -f "$SRCSET" ]]; then
    echo "ERROR: $SRCSET not found"
    exit 1
fi

loader_spec="/tmp/sw-cor24-hlasm-sourceset-$$.loader"

main_addr=589824
next_addr=528384
slot_count=0

: > "$loader_spec"

while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%;*}"
    line="${line%%#*}"

    set -- $line

    if [[ $# -eq 0 ]]; then
        continue
    fi

    case "$1" in
        MAIN)
            if [[ $# -ne 2 ]]; then
                echo "ERROR: MAIN expects: MAIN <file.hlasm>"
                exit 1
            fi

            src_part="$2"
            bin_part="${src_part%.hlasm}.bin"

            if [[ ! -f "$src_part" ]]; then
                echo "ERROR: $src_part not found"
                exit 1
            fi

            bash demos/make_bin.sh "$src_part" "$bin_part" >/dev/null
            printf 'MAIN %s@%s\n' "$bin_part" "$main_addr" >> "$loader_spec"
            ;;
        INCLUDE)
            if [[ $# -ne 3 ]]; then
                echo "ERROR: INCLUDE expects: INCLUDE <name> <file.hlasm>"
                exit 1
            fi

            src_part="$3"
            bin_part="${src_part%.hlasm}.bin"

            if [[ ! -f "$src_part" ]]; then
                echo "ERROR: $src_part not found"
                exit 1
            fi

            bash demos/make_bin.sh "$src_part" "$bin_part" >/dev/null

            slot_count=$(( slot_count + 1 ))
            printf 'SRCBUF %s,%s@%s\n' "$slot_count" "$bin_part" "$next_addr" >> "$loader_spec"
            printf 'INCLUDE %s,%s\n' "$2" "$slot_count" >> "$loader_spec"
            next_addr=$(( next_addr + 4096 ))
            ;;
        *)
            echo "ERROR: unknown sourceset directive '$1'"
            exit 1
            ;;
    esac
done < "$SRCSET"

exec bash reg-rs/run_bootstrap_loader.sh "$loader_spec" "$MAX_INSNS" "$@"
