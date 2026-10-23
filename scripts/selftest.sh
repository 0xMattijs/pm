#!/usr/bin/env bash
# Bootstrap a throwaway project with base + one layer, exactly as
# /pm:new-project does, then prove it works: stack checks, the task tracker,
# the hooks, and a no-op sync. Used by CI and for local template work.
#
# Usage: selftest.sh <layer> [path]   (path default: app)
set -euo pipefail
PM_HOME="$(cd "$(dirname "$0")/.." && pwd)"
layer="$1"; path="${2:-app}"
work="$(mktemp -d)"; dest="$work/demo"
trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.com
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.com

# Collapsible log groups on GitHub Actions, plain headers locally.
step() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::group::$*"; else echo "== $*"; fi; }
end() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::endgroup::"; fi; }

step "scaffold $layer at $path"
mkdir -p "$dest" && git -C "$dest" init -qb main
opts=()
case "$layer" in expo|flutter|ios-swift|android-kotlin) opts=(app_name=Demo bundle_id=com.example.demo) ;; esac
"$PM_HOME/scripts/scaffold.sh" pre "$layer" "$dest" "$path" demo com.example.demo
"$PM_HOME/scripts/apply-layer.sh" "$dest" base project_name=Demo
"$PM_HOME/scripts/apply-layer.sh" "$dest" "$layer" path="$path" "${opts[@]}"
"$PM_HOME/scripts/scaffold.sh" post "$layer" "$dest" "$path" demo com.example.demo
cd "$dest"
end

step "stack check"
scripts/check.sh "$layer"
end

step "tracker"
mkdir -p docs/phases/01-foundation
printf '## Goal\nx\n\n## Acceptance criteria\n- [ ] y\n\n## Scope\n- Owns: %s/a\n\n## Test plan\nunit\n' "$path" \
  | scripts/task.py new -p 01 -t "First" -w 1 >/dev/null
printf '## Goal\nx\n\n## Acceptance criteria\n- [ ] y\n\n## Scope\n- Owns: %s/b\n\n## Test plan\nunit\n' "$path" \
  | scripts/task.py new -p 01 -t "Second" -w 2 -d 01-01 >/dev/null
scripts/task.py lint -p 01
[ "$(scripts/task.py ready | cut -c1-5)" = "01-01" ]
scripts/task.py set 01-01 "done" >/dev/null
[ "$(scripts/task.py ready | cut -c1-5)" = "01-02" ]
scripts/task.py phases | grep -q in-progress
end

step "hooks"
export CLAUDE_PROJECT_DIR="$dest"
echo '{"tool_input":{"file_path":"/nonexistent"}}' | .claude/hooks/format.sh
transcript="$work/t.jsonl"
printf '{"type":"user","message":{"content":"Implement task 01-02."}}\n' > "$transcript"
out=$(printf '{"agent_type":"implementer","agent_transcript_path":"%s","stop_hook_active":false}' "$transcript" \
  | python3 .claude/hooks/subagent-guard.py)
echo "$out" | grep -q '"decision": "block"' || { echo "guard did not block an unfinished task" >&2; exit 1; }
end

step "sync (no-op)"
git add -A && git commit -qm "chore: bootstrap"
"$PM_HOME/scripts/sync.sh" >/dev/null
[ -z "$(git status --porcelain)" ]
end

echo "selftest $layer: ok"
