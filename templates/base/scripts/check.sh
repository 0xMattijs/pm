#!/usr/bin/env bash
# Runs every stack check in scripts/check.d/. Each stack layer adds one script.
# Usage: scripts/check.sh [layer...]   (no args = all layers)
set -uo pipefail
cd "$(dirname "$0")/.."

checks=()
if [ $# -gt 0 ]; then
  for l in "$@"; do checks+=("scripts/check.d/$l.sh"); done
else
  for f in scripts/check.d/*.sh; do [ -e "$f" ] && checks+=("$f"); done
fi

failed=()
for c in "${checks[@]}"; do
  echo "== $(basename "$c" .sh)"
  bash "$c" || failed+=("$(basename "$c" .sh)")
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED: ${failed[*]}" >&2
  exit 1
fi
echo "all checks passed"
