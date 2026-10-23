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
dest="$1"; layer="$2"; shift 2

data=(-d "layer=$layer")
path="."
for kv in "$@"; do
  data+=(-d "$kv")
  [[ "$kv" == path=* ]] && path="${kv#path=}"
done

uvx copier copy --quiet --defaults --vcs-ref HEAD "${data[@]}" "$SRC" "$dest"

cd "$dest"
chmod +x scripts/*.sh scripts/*.py scripts/check.d/*.sh .claude/hooks/*.sh .claude/hooks/format.d/*.sh 2>/dev/null || true

# Each layer contributes ignore rules. Non-root stacks get path-anchored rules.
ignores="$PM_HOME/ignores/$layer.txt"
if [ -f "$ignores" ]; then
  touch .gitignore
  grep -qxF "# pm:$layer" .gitignore || {
    printf '\n# pm:%s\n' "$layer" >> .gitignore
    while IFS= read -r line; do
      if [ "$path" = "." ] || [[ "$line" == !* ]]; then echo "$line"
      else echo "/${path%/}/$line"; fi
    done < "$ignores" >> .gitignore
  }
fi
echo "applied $layer (path=$path)"
