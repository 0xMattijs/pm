#!/usr/bin/env bash
# Update every template layer in a project to the latest template version.
# Usage: sync.sh [dest]   (default: current directory)
set -euo pipefail
cd "${1:-.}"
[ -z "$(git status --porcelain)" ] || { echo "working tree not clean; commit or stash first" >&2; exit 1; }

files=(.copier-answers.base.yml)
for f in .copier-answers.*.yml; do [ "$f" = .copier-answers.base.yml ] || files+=("$f"); done

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  echo "== ${f#.copier-answers.}"
  uvx copier update --quiet --defaults --vcs-ref HEAD --conflict inline --answers-file "$f"
done
chmod +x scripts/*.sh scripts/*.py scripts/check.d/*.sh .claude/hooks/*.sh .claude/hooks/format.d/*.sh 2>/dev/null || true

if grep -rlE '^(<<<<<<<|>>>>>>>) ' --exclude-dir=.git --exclude-dir=node_modules . 2>/dev/null; then
  echo "CONFLICTS: resolve the files listed above" >&2
  exit 2
fi
git status --short
