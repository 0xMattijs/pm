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
  # Same version rule as apply-layer.sh: newest release tag for a remote
  # source, HEAD for a local checkout, PM_TEMPLATE_REF to override.
  src=$(sed -n 's/^_src_path: //p' "$f")
  ref=()
  if [ -n "${PM_TEMPLATE_REF:-}" ]; then ref=(--vcs-ref "$PM_TEMPLATE_REF")
  elif [ -d "$src" ]; then ref=(--vcs-ref HEAD); fi
  before=$(sed -n 's/^_commit: //p' "$f")
  uvx copier update --quiet --defaults "${ref[@]}" --conflict inline --answers-file "$f" </dev/null || exit 1
  after=$(sed -n 's/^_commit: //p' "$f")
  echo "   $before -> $after"
  chmod +x scripts/*.sh scripts/*.py scripts/check.d/*.sh scripts/setup.d/*.sh .claude/hooks/*.sh .claude/hooks/format.d/*.sh 2>/dev/null || true
  conflicts=$(grep -rlE '^(<<<<<<<|>>>>>>>) ' --exclude-dir=.git --exclude-dir=node_modules . || true)
  if [ -n "$conflicts" ]; then
    echo "$conflicts" >&2
    echo "CONFLICTS in layer $layer: resolve the files above, commit, then rerun sync.sh" >&2
    exit 2
  fi
  git add -A
  git diff --cached --quiet || git commit -qm "chore(sync): update $layer layer to $after"
done
git log --oneline -n "${#files[@]}"
