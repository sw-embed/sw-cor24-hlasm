#!/usr/bin/env bash
# check_includes.sh <case> -- exercise the source config and INCLUDE limits.
#
#   members   32 members with 15-character names, all INCLUDEd from main
#   depth     INCLUDE nested 16 deep (ok) and 17 deep (ERROR)
#   location  ERROR lines name the member and line: inside a nested member,
#             and in main after an include returned (via a macro call)
#   config    a config block claiming 33 members stops with an ERROR, and
#             make_cfg.sh rejects a 16-character name
# See docs/limits-and-lifting-plan.md (L19-L21, M7).
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hlasm-includes.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# run <sourceset> <budget>: run hlasm and print its output without the
# loader and instruction-count lines.
run() {
    bash reg-rs/run_bootstrap_sourceset.sh "$1" "$2" -q 2>&1 \
        | tr -d '\r' | grep -v -e '^Executed' -e '^Loaded ' -e '^$' || true
}

# chain <dir> <members> <depth> [bad]: main INCLUDEs mem_n_padded_01,
# which includes _02 and so on <depth> deep; the remaining members are
# INCLUDEd one after another from main. With "bad" the deepest member has
# a division by zero on its line 3.
chain() {
    local dir="$1" n="$2" d="$3" bad="${4:-}"
    local i nm
    mkdir -p "$dir"
    printf 'MAIN %s/top.hlasm\n' "$dir" > "$dir/set.sourceset"
    printf '; main\nINCLUDE mem_n_padded_01\n' > "$dir/top.hlasm"
    for ((i = 1; i <= n; i++)); do
        nm="$(printf 'mem_n_padded_%02d' "$i")"
        {
            printf '; in %s\n nop ; %d\n' "$nm" "$i"
            if ((i < d)); then printf 'INCLUDE mem_n_padded_%02d\n' $((i + 1)); fi
            if ((i == d)) && [[ "$bad" == bad ]]; then printf 'SET X,1/0\n'; fi
            printf ' nop ; end %d\n' "$i"
        } > "$dir/$nm.hlasm"
        if ((i > d)); then printf 'INCLUDE %s\n' "$nm" >> "$dir/top.hlasm"; fi
        printf 'INCLUDE %s %s/%s.hlasm\n' "$nm" "$dir" "$nm" >> "$dir/set.sourceset"
    done
    printf ' nop ; main end\n' >> "$dir/top.hlasm"
}

case "${1:-}" in
    members)
        chain "$WORK/m" 32 1
        run "$WORK/m/set.sourceset" 40000000 > "$WORK/m.txt"
        printf 'members: %s nop lines (expect 65), last: %s\n' \
            "$(grep -c 'nop' "$WORK/m.txt" || true)" "$(tail -1 "$WORK/m.txt")"
        grep -- '; in mem_n_padded_32' "$WORK/m.txt"
        ;;
    depth)
        chain "$WORK/d16" 16 16
        run "$WORK/d16/set.sourceset" 20000000 > "$WORK/d16.txt"
        printf 'depth_16: %s nop lines (expect 33), last: %s\n' \
            "$(grep -c 'nop' "$WORK/d16.txt" || true)" "$(tail -1 "$WORK/d16.txt")"
        chain "$WORK/d17" 17 17
        printf 'depth_17: %s\n' "$(run "$WORK/d17/set.sourceset" 20000000 | grep -m1 '^ERROR:')"
        ;;
    location)
        chain "$WORK/l" 5 3 bad
        printf 'nested: %s\n' "$(run "$WORK/l/set.sourceset" 4000000 | grep -m1 '^ERROR:')"
        mkdir -p "$WORK/r"
        printf '; l1\nCOPY lib\n; l3\n; l4\nMACRO M\n SET Y,1/0\nMEND\n M\n' > "$WORK/r/prog.hlasm"
        printf '; lib 1\n; lib 2\n' > "$WORK/r/lib.hlasm"
        printf 'MAIN %s/prog.hlasm\nCOPY lib %s/lib.hlasm\n' "$WORK/r" "$WORK/r" > "$WORK/r/set.sourceset"
        printf 'after_return: %s\n' "$(run "$WORK/r/set.sourceset" 4000000 | grep -m1 '^ERROR:')"
        ;;
    config)
        printf ' nop\n' > "$WORK/main.bin"
        { printf '\041'; head -c 24 /dev/zero; } > "$WORK/bad.cfg"
        printf 'count_33: %s\n' "$(scripts/run-kernel.sh hlasm.s \
            --load-binary "$WORK/main.bin@524288" --load-binary "$WORK/bad.cfg@520192" \
            --speed 0 -n 400000 -q 2>&1 | tr -d '\r' | grep -m1 '^ERROR:')"
        printf 'extra 528384 1\ninclude 1 abcdefghijklmnop\n' > "$WORK/long.cfg.txt"
        printf 'name_16: %s\n' "$(bash reg-rs/make_cfg.sh "$WORK/long.cfg.txt" "$WORK/long.cfg" || true)"
        ;;
    *)
        echo "Usage: $0 members|depth|location|config"
        exit 1
        ;;
esac
