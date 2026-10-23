#!/usr/bin/env bash
# Apply one template layer to a project.
# Usage: apply-layer.sh <dest> <layer> [key=value ...]
#   apply-layer.sh ~/projects/acme base project_name=Acme tracker=github
#   apply-layer.sh ~/projects/acme python-uv path=api
# PM_TEMPLATE_SRC overrides the template source (default: this repo). Set it
# to a git URL such as gh:owner/pm so answers files don't record a local path.
set -euo pipefail
PM_HOME="$(cd "$(dirname "$0")/.." && pwd)"
# Copier needs a git source to record versions for later updates. An installed
# plugin lives in a non-git cache, so fall back to the development checkout.
if [ -n "${PM_TEMPLATE_SRC:-}" ]; then SRC="$PM_TEMPLATE_SRC"
elif git -C "$PM_HOME" rev-parse --git-dir >/dev/null 2>&1; then SRC="$PM_HOME"
elif git -C "$HOME/projects/pm" rev-parse --git-dir >/dev/null 2>&1; then SRC="$HOME/projects/pm"
else echo "set PM_TEMPLATE_SRC to the pm git repo (path or gh:owner/pm)" >&2; exit 1; fi
# A dirty local template makes Copier record a throwaway commit that later
# updates can't find. Template changes must be committed first.
if [ -d "$SRC" ] && [ -n "$(git -C "$SRC" status --porcelain -- copier.yml templates)" ]; then
  echo "uncommitted template changes in $SRC; commit them first" >&2; exit 1
fi
# Which template version to render. A remote source uses its newest release
# tag (Copier's default when no ref is given). A local checkout renders HEAD,
# for template development. PM_TEMPLATE_REF overrides both: a tag, or HEAD.
ref=()
if [ -n "${PM_TEMPLATE_REF:-}" ]; then ref=(--vcs-ref "$PM_TEMPLATE_REF")
elif [ -d "$SRC" ]; then ref=(--vcs-ref HEAD)
elif git -C "$PM_HOME" rev-parse --git-dir >/dev/null 2>&1; then
  # Changes in this checkout after the newest release won't be included.
  latest=$(git -C "$PM_HOME" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
  if [ -n "$latest" ]; then
    unreleased=$(git -C "$PM_HOME" rev-list --count "$latest..HEAD" -- copier.yml templates ignores 2>/dev/null || echo 0)
    [ "$unreleased" = 0 ] || echo "note: using release $latest; $unreleased newer template commit(s) aren't released (scripts/release.sh)" >&2
  fi
fi
dest="$1"; layer="$2"; shift 2

data=(-d "layer=$layer")
path="."
for kv in "$@"; do
  data+=(-d "$kv")
  [[ "$kv" == path=* ]] && path="${kv#path=}"
done

if [ -f "$dest/.copier-answers.$layer.yml" ]; then
  echo "layer $layer already applied; use sync.sh to update it" >&2; exit 1
fi
# Layers own disjoint files, so --overwrite only replaces leftovers from a
# failed earlier run. stdin is closed so Copier can never block on a prompt.
uvx copier copy --quiet --defaults --overwrite "${ref[@]}" "${data[@]}" "$SRC" "$dest" </dev/null

cd "$dest"
chmod +x scripts/*.sh scripts/*.py scripts/check.d/*.sh scripts/setup.d/*.sh .claude/hooks/*.sh .claude/hooks/format.d/*.sh 2>/dev/null || true

# Each layer contributes ignore rules. Non-root stacks get path-anchored rules.
ignores="$PM_HOME/ignores/$layer.txt"
if [ -f "$ignores" ]; then
  touch .gitignore
  grep -qxF "# pm:$layer" .gitignore || {
    printf '\n# pm:%s\n' "$layer" >> .gitignore
    while IFS= read -r line; do
      if [ "$path" = "." ] || [[ "$line" == !* ]]; then echo "$line"
      else echo "/${path%/}/**/$line"; fi
    done < "$ignores" >> .gitignore
  }
fi
echo "applied $layer (path=$path)"
