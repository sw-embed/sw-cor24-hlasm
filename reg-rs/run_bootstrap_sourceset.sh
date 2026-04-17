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

root_dir="."
main_addr=589824
next_addr=528384
align_bytes=256
slot_count=0

: > "$loader_spec"

align_up() {
    local value="$1"
    local align="$2"
    echo $(( ((value + align - 1) / align) * align ))
}

resolve_path() {
    local path="$1"

    case "$path" in
        /*) echo "$path" ;;
        *) echo "$root_dir/$path" ;;
    esac
}

while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%;*}"
    line="${line%%#*}"

    set -- $line

    if [[ $# -eq 0 ]]; then
        continue
    fi

    case "$1" in
        ROOT)
            if [[ $# -ne 2 ]]; then
                echo "ERROR: ROOT expects: ROOT <dir>"
                exit 1
            fi

            root_dir="$2"
            ;;
        MAINADDR)
            if [[ $# -ne 2 ]]; then
                echo "ERROR: MAINADDR expects: MAINADDR <addr>"
                exit 1
            fi

            main_addr="$2"
            ;;
        EXTRAADDR)
            if [[ $# -ne 2 ]]; then
                echo "ERROR: EXTRAADDR expects: EXTRAADDR <addr>"
                exit 1
            fi

            next_addr="$2"
            ;;
        ALIGN)
            if [[ $# -ne 2 ]]; then
                echo "ERROR: ALIGN expects: ALIGN <bytes>"
                exit 1
            fi

            align_bytes="$2"
            ;;
        MAIN)
            if [[ $# -ne 2 ]]; then
                echo "ERROR: MAIN expects: MAIN <file.hlasm>"
                exit 1
            fi

            src_part="$(resolve_path "$2")"
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

            src_part="$(resolve_path "$3")"
            bin_part="${src_part%.hlasm}.bin"

            if [[ ! -f "$src_part" ]]; then
                echo "ERROR: $src_part not found"
                exit 1
            fi

            bash demos/make_bin.sh "$src_part" "$bin_part" >/dev/null
            size_part="$(wc -c < "$bin_part")"

            slot_count=$(( slot_count + 1 ))
            printf 'SRCBUF %s,%s@%s\n' "$slot_count" "$bin_part" "$next_addr" >> "$loader_spec"
            printf 'INCLUDE %s,%s\n' "$2" "$slot_count" >> "$loader_spec"
            next_addr="$(align_up $(( next_addr + size_part )) "$align_bytes")"
            ;;
        *)
            echo "ERROR: unknown sourceset directive '$1'"
            exit 1
            ;;
    esac
done < "$SRCSET"

exec bash reg-rs/run_bootstrap_loader.sh "$loader_spec" "$MAX_INSNS" "$@"
