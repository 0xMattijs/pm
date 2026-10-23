#!/usr/bin/env bash
# Put the checkout on the top of the open wave stack (or main), up to date
# with the remote, so an unattended run continues where the last one stopped.
# Shared by the local agent loop and the agent-run workflow.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

git fetch --quiet --prune origin
top=$(gh pr list --state open --search "head:wave/" --json headRefName -q '.[].headRefName' | sort -V | tail -1)
branch="${top:-main}"
git switch --quiet "$branch" 2>/dev/null || git switch --quiet -c "$branch" "origin/$branch"
git reset --quiet --hard "origin/$branch"
git clean --quiet -fd
echo "on branch: $branch"
