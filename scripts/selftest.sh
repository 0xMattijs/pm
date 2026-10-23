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
# Test this checkout's committed templates, not whatever is pushed.
export PM_TEMPLATE_SRC="$PM_HOME"
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

step "ci workflow"
# GitHub matches paths without a leading "./", so a root stack needs "**".
glob="$path/**"; [ "$path" = "." ] && glob="**"
grep -qF "paths: [\"$glob\"," ".github/workflows/ci-$layer.yml" \
  || { echo "ci-$layer.yml paths filter should start with $glob" >&2; exit 1; }
end

step "stack check"
if [ "$layer" = ts-next ]; then
  # A clean checkout has no generated route types; the check must create them.
  printf 'export type RootLayoutProps = LayoutProps<"/">;\n' > "$path/src/typegen-probe.ts"
  rm -rf "$path/.next"
fi
scripts/check.sh "$layer"
[ "$layer" = ts-next ] && rm "$path/src/typegen-probe.ts"
end

step "tracker"
mkdir -p docs/phases/01-foundation
printf '## Goal\nx\n\n## Acceptance criteria\n- [ ] y\n\n## Scope\n- Owns: %s/a\n\n## Test plan\nunit\n\n## Verify\n`true` exits 0\n' "$path" \
  | scripts/task.py new -p 01 -t "First" -w 1 >/dev/null
printf '## Goal\nx\n\n## Acceptance criteria\n- [ ] y\n\n## Scope\n- Owns: %s/b\n\n## Test plan\nunit\n\n## Verify\n`true` exits 0\n' "$path" \
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

step "agent precheck"
# Phase 01 has a ready task, so a scheduled run has work. gh has no remote
# here, so PR and issue checks are skipped with a note.
pre=$(python3 scripts/agent-precheck.py)
echo "$pre" | grep -q '^run=true' || { echo "precheck should find ready work: $pre" >&2; exit 1; }
end

step "risk gate"
git add -A && git commit -qm "chore: bootstrap"
echo "note" > NOTES.md && git add NOTES.md && git commit -qm "docs: note"
scripts/risk.py HEAD~1..HEAD >/dev/null || { echo "small docs change should be low risk" >&2; exit 1; }
mkdir -p src/auth && echo "x" > src/auth/login.txt && git add -A && git commit -qm "feat: auth"
if scripts/risk.py HEAD~1..HEAD >/dev/null; then echo "auth change should be high risk" >&2; exit 1; fi
if scripts/risk.py nonexistent..HEAD >/dev/null 2>&1; then echo "bad range must fail closed" >&2; exit 1; fi
git reset -q --hard HEAD~2
end

step "sync (no-op)"
"$PM_HOME/scripts/sync.sh" >/dev/null
[ -z "$(git status --porcelain)" ]
end

echo "selftest $layer: ok"
