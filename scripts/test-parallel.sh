#!/usr/bin/env bash
# Exercise parallel execution end to end in a throwaway repo, without agents:
# dependency-driven dispatch, worktrees per task, merge-forward between waves,
# concurrent phases, the wait rule for multiple unmerged dependencies, file
# ownership conflicts, the agent cap, and the width lint.
set -euo pipefail
PM_HOME="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export PM_TEMPLATE_SRC="$PM_HOME"
d="$work/p"; mkdir -p "$d" && git -C "$d" init -qb main
"$PM_HOME/scripts/apply-layer.sh" "$d" base project_name=P >/dev/null
cd "$d"
T="python3 scripts/task.py"; W="python3 scripts/waves.py"
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
ids() { $T "$@" | cut -c1-5 | tr '\n' ' ' | sed 's/ $//'; }

cat > ROADMAP.md <<'EOF'
# Roadmap
## Milestone 1: MVP
| Phase | Depends | Goal |
|---|---|---|
| 01-foundation | - | skeleton |
| 02-signup | 01 | signup |
| 03-profile | 01 | profile |
| 04-dashboard | 02, 03 | dashboard |
## Milestone 2: Teams
| Phase | Depends | Goal |
|---|---|---|
| 05-teams | 04 | teams |
EOF
contract() { printf '## Goal\nx\n\n## Acceptance criteria\n- [ ] y\n\n## Scope\n- Owns: %s\n\n## Test plan\nunit\n\n## Verify\n`true`\n' "$1"; }
mkdir -p docs/phases/01-foundation
contract src/a | $T new -p 01 -t A -w 1 >/dev/null
contract src/b | $T new -p 01 -t B -w 2 -d 01-01 >/dev/null
contract src/c | $T new -p 01 -t C -w 2 -d 01-01 >/dev/null
contract src/d | $T new -p 01 -t D -w 3 -d 01-02 >/dev/null
git add -A && git commit -qm init

# Width lint: 4 tasks, chain of 3.
if $T lint -p 01 >/dev/null; then fail "lint should flag a narrow plan"; fi
echo "Sequential: test fixture" > docs/phases/01-foundation/PHASE.md
$T lint -p 01 >/dev/null || fail "Sequential: should silence the width check"
ok "width lint flags narrow plans and honors Sequential:"

[ "$(ids ready)" = "01-01" ] || fail "only 01-01 should be ready, got: $(ids ready)"
ok "phase 02 waits for phase 01"

work_on() {  # work_on <id> <file>: start a task, commit a file in its worktree
  local p; p=$($W start "$1"); $T set "$1" doing >/dev/null
  echo "$1" > "$p/$2"; git -C "$p" add -A; git -C "$p" commit -qm "feat: $1 [$1]"
}
finish() { $W merge "$1" >/dev/null; $T set "$1" done >/dev/null; }

work_on 01-01 a.txt; finish 01-01
[ "$(ids ready)" = "01-02 01-03" ] || fail "01-02 and 01-03 should be ready, got: $(ids ready)"
ok "tasks start when their own dependencies are done"

work_on 01-02 b.txt; work_on 01-03 c.txt
finish 01-02
[ "$(ids ready)" = "01-04" ] || fail "01-04 should start before wave 2 finishes, got: $(ids ready)"
ok "no wave barrier: 01-04 is ready while 01-03 still runs"

work_on 01-04 d.txt
finish 01-03; finish 01-04
for f in a b c d; do git cat-file -e "wave/01-3:$f.txt" 2>/dev/null || fail "wave/01-3 is missing $f.txt"; done
ok "merge-forward: the top wave contains every earlier task"

[ "$($T next-phases | awk '{print $1}' | tr '\n' ' ')" = "02-signup 03-profile " ] || fail "02 and 03 should be startable: $($T next-phases)"
ok "independent phases 02 and 03 are startable together"

[ "$($W base 02)" = "wave/01-3" ] || fail "phase 02 should stack on wave/01-3"
ok "a phase stacks on its unmerged dependency"

mkdir -p docs/phases/02-signup docs/phases/03-profile
contract src/signup | $T new -p 02 -t S -w 1 >/dev/null
contract src/a/override | $T new -p 03 -t P -w 1 >/dev/null
contract src/profile | $T new -p 03 -t Q -w 1 >/dev/null
work_on 02-01 s.txt; work_on 03-01 p.txt; finish 02-01; finish 03-01
$T set 03-02 done >/dev/null
set +e; $W base 04 >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 3 ] || fail "phase 04 must wait while 02 and 03 are both unmerged (rc=$rc)"
ok "a phase with two unmerged dependencies waits"

mkdir -p docs/phases/04-dashboard
contract src/a | $T new -p 04 -t X -w 1 >/dev/null
contract src/dash | $T new -p 04 -t Y -w 1 >/dev/null
$T set 04-01 doing >/dev/null
contract src/a/inner | $T new -p 04 -t Z -w 1 >/dev/null
[ "$(ids ready -p 04)" = "04-02" ] || fail "04-03 overlaps running 04-01 and must wait, got: $(ids ready -p 04)"
ok "file ownership overlap with a running task blocks dispatch"

echo '{"max_agents": 1}' > .claude/pm.json
[ -z "$(ids ready --slots)" ] || fail "one agent busy and max_agents=1 means no free slots"
ok "--slots respects max_agents"

for i in 04-01 04-02 04-03; do $T set $i done >/dev/null; done
[ -z "$($T next-phases)" ] || fail "milestone 2 must not start without /replan: $($T next-phases)"
python3 scripts/agent-precheck.py | grep -q 'milestone boundary before 05-teams' || fail "precheck should report the boundary"
ok "chaining stops at the milestone boundary"

echo "test-parallel: all passed"
