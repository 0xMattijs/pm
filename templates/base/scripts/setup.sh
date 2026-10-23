#!/usr/bin/env bash
# Install the toolchains this project needs on a fresh Linux runner, for
# scheduled agent runs. Each stack layer adds scripts/setup.d/<layer>.sh.
# In GitHub Actions, PATH additions go through $GITHUB_PATH.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

add_path() {
  export PATH="$1:$PATH"
  if [ -n "${GITHUB_PATH:-}" ]; then echo "$1" >> "$GITHUB_PATH"; fi
}
export -f add_path

for f in scripts/setup.d/*.sh; do
  [ -e "$f" ] || continue
  echo "== setup $(basename "$f" .sh)"
  bash "$f"
done
