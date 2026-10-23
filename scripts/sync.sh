#!/usr/bin/env bash
# Update every template layer in a project to the latest template version.
# Usage: sync.sh [dest]   (default: current directory)
set -euo pipefail
cd "${1:-.}"
[ -z "$(git status --porcelain)" ] || { echo "working tree not clean; commit or stash first" >&2; exit 1; }

files=(.copier-answers.base.yml)
for f in .copier-answers.*.yml; do [ "$f" = .copier-answers.base.yml ] || files+=("$f"); done

# Copier refuses to update a dirty tree, so commit each layer before the next.
# Run this on a dedicated branch; the sync-workflow skill creates one.
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  layer="${f#.copier-answers.}"; layer="${layer%.yml}"
  echo "== $layer"
  uvx copier update --quiet --defaults --vcs-ref HEAD --conflict inline --answers-file "$f" </dev/null || exit 1
  chmod +x scripts/*.sh scripts/*.py scripts/check.d/*.sh .claude/hooks/*.sh .claude/hooks/format.d/*.sh 2>/dev/null || true
  if git grep -lE '^(<<<<<<<|>>>>>>>) ' -- . ':!*.lock' >/dev/null 2>&1 || \
     grep -rlE '^(<<<<<<<|>>>>>>>) ' --exclude-dir=.git --exclude-dir=node_modules . >/dev/null 2>&1; then
    grep -rlE '^(<<<<<<<|>>>>>>>) ' --exclude-dir=.git --exclude-dir=node_modules . >&2
    echo "CONFLICTS in layer $layer: resolve the files above, commit, then rerun sync.sh" >&2
    exit 2
  fi
  git add -A
  git diff --cached --quiet || git commit -qm "chore(sync): update $layer layer"
done
git log --oneline -n "${#files[@]}"
