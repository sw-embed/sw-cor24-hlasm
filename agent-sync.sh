#!/usr/bin/env bash
# agent-sync.sh -- pick up upstream merges and delete merged pr/ branches.
#
# Usage: ./agent-sync.sh
#
# Fetches origin, fast-forwards local dev to origin/dev, and deletes
# local pr/<slug> branches whose tip is already an ancestor of
# origin/dev (i.e. upstream has merged them). Returns to the starting
# branch if it still exists.
#
# Safe to re-run: no-op when nothing is merged.

set -euo pipefail
cd "$(dirname "$0")"

git fetch origin --prune

merged_prs=()
while IFS= read -r br; do
    [[ -z "$br" ]] && continue
    if git merge-base --is-ancestor "$br" origin/dev; then
        merged_prs+=("$br")
    fi
done < <(git for-each-ref --format='%(refname:short)' refs/heads/pr/)

dev_local=$(git rev-parse --verify dev 2>/dev/null || true)
dev_remote=$(git rev-parse --verify origin/dev)

if [[ "$dev_local" = "$dev_remote" && ${#merged_prs[@]} -eq 0 ]]; then
    echo "Nothing to sync: dev is up to date, no merged pr/ branches."
    exit 0
fi

if [[ -n "$dev_local" ]] && ! git merge-base --is-ancestor dev origin/dev; then
    echo "ERROR: local dev has diverged from origin/dev. Resolve manually." >&2
    exit 1
fi

prior=$(git branch --show-current)
git switch dev

if [[ "$dev_local" != "$dev_remote" ]]; then
    git merge --ff-only origin/dev
fi

for br in "${merged_prs[@]}"; do
    git branch -d "$br"
done

if [[ -n "$prior" && "$prior" != dev ]] && git show-ref --verify --quiet "refs/heads/$prior"; then
    git switch "$prior"
fi

echo "agent-sync complete."
