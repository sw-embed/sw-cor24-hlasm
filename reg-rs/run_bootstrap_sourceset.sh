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

cfg_txt="/tmp/sw-cor24-hlasm-sourceset-$$.cfg.txt"
cfg_bin="/tmp/sw-cor24-hlasm-sourceset-$$.cfg"
spec_stack="|"

root_dir="."
main_addr=589824
next_addr=528384
align_bytes=256
slot_count=0
load_args=()

: > "$cfg_txt"

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

resolve_path_from() {
    local base_dir="$1"
    local path="$2"

    case "$path" in
        /*) echo "$path" ;;
        *) echo "$base_dir/$path" ;;
    esac
}

process_sourceset() {
    local spec_file="$1"
    local spec_dir
    spec_dir="$(cd "$(dirname "$spec_file")" && pwd)"
    spec_file="$(cd "$spec_dir" && pwd)/$(basename "$spec_file")"

    case "$spec_stack" in
        *"|$spec_file|"*)
            echo "ERROR: recursive sourceset include detected: $spec_file"
            exit 1
            ;;
    esac

    spec_stack="${spec_stack}${spec_file}|"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%;*}"
        line="${line%%#*}"

        set -- $line

        if [[ $# -eq 0 ]]; then
            continue
        fi

        case "$1" in
            PROFILE)
                if [[ $# -ne 2 ]]; then
                    echo "ERROR: PROFILE expects: PROFILE <file>"
                    exit 1
                fi

                process_sourceset "$(resolve_path_from "$spec_dir" "$2")"
                ;;
            SOURCESET)
                if [[ $# -ne 2 ]]; then
                    echo "ERROR: SOURCESET expects: SOURCESET <file>"
                    exit 1
                fi

                process_sourceset "$(resolve_path_from "$spec_dir" "$2")"
                ;;
            ROOT)
                if [[ $# -ne 2 ]]; then
                    echo "ERROR: ROOT expects: ROOT <dir>"
                    exit 1
                fi

                root_dir="$(resolve_path_from "$spec_dir" "$2")"
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
                size_part="$(wc -c < "$bin_part")"
                printf 'main %s %s\n' "$main_addr" "$size_part" >> "$cfg_txt"
                load_args+=("--load-binary" "${bin_part}@${main_addr}")
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
                printf 'extra %s %s\n' "$next_addr" "$size_part" >> "$cfg_txt"
                printf 'include %s %s\n' "$slot_count" "$2" >> "$cfg_txt"
                load_args+=("--load-binary" "${bin_part}@${next_addr}")
                next_addr="$(align_up $(( next_addr + size_part )) "$align_bytes")"
                ;;
            *)
                echo "ERROR: unknown sourceset directive '$1'"
                exit 1
                ;;
        esac
    done < "$spec_file"

    spec_stack="${spec_stack%$spec_file|}"
}

process_sourceset "$SRCSET"

bash reg-rs/make_cfg.sh "$cfg_txt" "$cfg_bin"

exec cor24-run --run hlasm.s \
    "${load_args[@]}" \
    --load-binary "${cfg_bin}@520192" \
    --stack-kilobytes 3 \
    --speed 0 \
    -n "$MAX_INSNS" \
    "$@"
