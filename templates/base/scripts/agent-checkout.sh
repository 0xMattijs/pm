#!/usr/bin/env bash
# Bring an unattended checkout up to date before an agent run. The main
# checkout stays on main; waves and tasks live in their own worktrees, which
# scripts/waves.py creates. Shared by the local agent loop and agent-run.yml.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

git fetch --quiet --prune origin
git switch --quiet main 2>/dev/null || git switch --quiet -c main origin/main
# With the files tracker, uncommitted task state in docs/phases can be newer
# than main's. Copy it aside, fast-forward, put it back, then let
# pull-tracker take the most advanced copy of each task from every branch.
keep=$(mktemp -d)
[ -d docs/phases ] && cp -r docs/phases "$keep/"
git checkout --quiet -- docs/phases 2>/dev/null || true
git clean --quiet -fd -- docs/phases
git merge --quiet --ff-only origin/main
[ -d "$keep/phases" ] && cp -r "$keep/phases/." docs/phases/
rm -rf "$keep"
python3 scripts/waves.py pull-tracker
git worktree prune
echo "on main at $(git rev-parse --short HEAD); open wave PRs: $(gh pr list --state open --search 'head:wave/' --json number -q 'length' 2>/dev/null || echo '?')"
