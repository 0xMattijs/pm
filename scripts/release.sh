#!/usr/bin/env bash
# Cut a pm release. Projects bootstrap and sync from the newest release tag,
# so a release is what makes template changes reach them.
#
# Usage: release.sh <X.Y.Z> [--dry-run]
#
# Refuses unless: you're on main, the tree is clean, main matches origin, and
# template CI passed on this exact commit. Then it bumps the plugin version,
# prepends the changelog (from Conventional Commits since the last tag),
# commits, tags vX.Y.Z, pushes, and creates a GitHub release.
#
# To undo a bad release, roll forward: revert the change and release a patch.
# Copier doesn't downgrade projects.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

version="${1:-}"; dry="${2:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: release.sh <X.Y.Z> [--dry-run]" >&2; exit 1; }
tag="v$version"
fail() { echo "release: $*" >&2; exit 1; }

prev=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
if [ -n "$prev" ]; then
  newest=$(printf '%s\n%s\n' "${prev#v}" "$version" | sort -V | tail -1)
  [ "$newest" = "$version" ] && [ "${prev#v}" != "$version" ] || fail "$tag must be newer than $prev"
fi

[ "$(git branch --show-current)" = main ] || fail "switch to main first"
[ -z "$(git status --porcelain)" ] || fail "working tree not clean"
git fetch --quiet origin main --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main differs from origin/main; push or pull first"

sha=$(git rev-parse HEAD)
ci=$(gh run list --workflow templates.yml --commit "$sha" --json status,conclusion -q '.[0] | "\(.status) \(.conclusion)"' 2>/dev/null || true)
case "$ci" in
  "completed success") ;;
  "") fail "no template CI run for ${sha:0:7} yet; push and wait for it" ;;
  *) fail "template CI for ${sha:0:7} is '$ci'; it must pass first" ;;
esac

# Changelog section from Conventional Commits since the previous release.
range="${prev:+$prev..}HEAD"
section() {  # section <title> <regex>
  local lines
  lines=$(git log --no-merges --format='%s' "$range" | grep -E "$2" | grep -v '^chore(release)' | sed -E 's/^[a-z]+(\([^)]*\))?!?: /- /' || true)
  [ -z "$lines" ] || printf '### %s\n\n%s\n\n' "$1" "$lines"
}
notes="$(section Added '^feat')$(section Fixed '^fix')$(section Changed '^(docs|refactor|perf|chore|ci|test|build)')"
[ -n "$notes" ] || notes="- Maintenance release."$'\n'

echo "== $tag (previous: ${prev:-none})"
printf '%s\n' "$notes"
[ "$dry" = "--dry-run" ] && { echo "(dry run: nothing changed)"; exit 0; }

python3 - "$version" <<'PY'
import json, sys
v = sys.argv[1]
for path, keys in ((".claude-plugin/plugin.json", ["version"]),
                   (".claude-plugin/marketplace.json", ["metadata", "version"])):
    data = json.load(open(path))
    node = data
    for k in keys[:-1]:
        node = node[k]
    node[keys[-1]] = v
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
PY

{
  echo "# Changelog"
  echo
  echo "## $tag ($(date +%Y-%m-%d))"
  echo
  printf '%s' "$notes"
  [ -f CHANGELOG.md ] && sed '1{/^# Changelog$/d}' CHANGELOG.md | sed '1{/^$/d}'
} > CHANGELOG.md.new && mv CHANGELOG.md.new CHANGELOG.md

git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
git commit -qm "chore(release): $tag"
git tag -a "$tag" -m "$tag"
git push --quiet origin main "$tag"
gh release create "$tag" --title "$tag" --notes "$notes" >/dev/null
echo "released $tag: $(gh release view "$tag" --json url -q .url)"
