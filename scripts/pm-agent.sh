#!/usr/bin/env bash
# Local agent loop: runs unattended agent passes for registered projects on
# this machine, so scheduled work costs no GitHub Actions minutes.
#
#   pm-agent.sh add <owner/repo>      register a project
#   pm-agent.sh remove <owner/repo>   unregister it
#   pm-agent.sh list                  show projects and their last result
#   pm-agent.sh run [owner/repo]      one pass now (all projects, or one)
#   pm-agent.sh install [minutes]     systemd user timer (default every 30 min)
#   pm-agent.sh uninstall             remove the timer
#   pm-agent.sh logs [owner/repo]     follow the latest log
#
# Each project gets its own clone under $PM_AGENT_HOME, never your working
# copy. A pass runs the no-LLM precheck first and starts Claude only when there
# is work. Settings come from ~/.config/pm/agent.env, for example
# ANTHROPIC_API_KEY=... (API billing instead of your plan's limits),
# PM_AGENT_MAX_HOURS=5, or GH_TOKEN=... when the timer can't reach the
# keyring that holds your gh login.
set -uo pipefail

CONF_DIR="${PM_AGENT_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/pm}"
PROJECTS="$CONF_DIR/agent-projects"
ENV_FILE="$CONF_DIR/agent.env"
PM_AGENT_HOME="${PM_AGENT_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/pm/agents}"
LOG_DIR="${PM_AGENT_LOGS:-${XDG_STATE_HOME:-$HOME/.local/state}/pm/agent-logs}"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
mkdir -p "$CONF_DIR" "$PM_AGENT_HOME" "$LOG_DIR"
touch "$PROJECTS"
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && set -a && . "$ENV_FILE" && set +a

slug() { echo "${1//\//__}"; }

# One pass for one project, in a subshell so its cd never leaks. Prints the
# log; the exit code is the pass's (0 also when there was nothing to do).
pass() (
  local repo="$1" dir="$2" pre prompt rc
  echo "== $(date -Is) $repo"
  if [ ! -d "$dir/.git" ]; then gh repo clone "$repo" "$dir" -- --quiet || exit 1; fi
  cd "$dir" || exit 1
  git fetch --quiet origin && git checkout --quiet origin/main 2>/dev/null
  if [ ! -f scripts/agent-checkout.sh ]; then
    echo "reason=not a pm project, or created before agent runs existed: run /pm:sync-workflow in it"
    exit 1
  fi
  bash scripts/agent-checkout.sh || exit 1

  pre=$(python3 scripts/agent-precheck.py)
  echo "$pre"
  if ! grep -q '^run=true' <<<"$pre"; then echo "nothing to do"; exit 0; fi

  prompt="$(cat .claude/agent-run.md)

Precheck: $(sed -n 's/^reason=//p' <<<"$pre")
Mode: ${PM_AGENT_MODE:-auto}"
  rc=0
  timeout --signal=INT "${PM_AGENT_MAX_HOURS:-5}h" claude -p "$prompt" \
    --max-turns 1500 \
    --allowedTools Bash Read Edit Write MultiEdit Grep Glob Agent Skill TodoWrite WebFetch WebSearch \
    --disallowedTools "Bash(gh pr merge:*)" "Bash(git push --force:*)" "Bash(git push -f:*)" "Bash(git push origin main:*)" AskUserQuestion \
    || rc=$?
  echo "== claude exit $rc at $(date -Is)"
  exit "$rc"
)

run_one() {
  local repo="$1" log lock rc
  log="$LOG_DIR/$(slug "$repo")-$(date +%Y%m%d-%H%M%S).log"
  lock="$PM_AGENT_HOME/$(slug "$repo").lock"

  exec 9>"$lock"
  if ! flock -n 9; then echo "$repo: previous run still active, skipping"; return 0; fi

  rc=0
  pass "$repo" "$PM_AGENT_HOME/$(slug "$repo")" >"$log" 2>&1 || rc=$?
  ln -sf "$log" "$LOG_DIR/$(slug "$repo")-latest.log"
  echo "$repo: exit $rc, $(sed -n 's/^reason=//p' "$log" | head -1)"
  return "$rc"
}

case "${1:-}" in
  add)
    [ -n "${2:-}" ] || { echo "usage: pm-agent.sh add <owner/repo>" >&2; exit 1; }
    gh repo view "$2" --json name >/dev/null || exit 1
    grep -qxF "$2" "$PROJECTS" || echo "$2" >> "$PROJECTS"
    echo "added $2" ;;
  remove)
    grep -vxF "${2:-}" "$PROJECTS" > "$PROJECTS.tmp"; mv "$PROJECTS.tmp" "$PROJECTS"
    echo "removed ${2:-}" ;;
  list)
    while read -r repo; do
      [ -n "$repo" ] || continue
      latest="$LOG_DIR/$(slug "$repo")-latest.log"
      when=$([ -e "$latest" ] && date -r "$latest" '+%F %H:%M' || echo never)
      echo "$repo  last run: $when  $([ -e "$latest" ] && grep -m1 '^reason=' "$latest" | cut -d= -f2-)"
    done < "$PROJECTS" ;;
  run)
    if [ -n "${2:-}" ]; then run_one "$2"; exit $?; fi
    status=0
    while read -r repo; do [ -n "$repo" ] && { run_one "$repo" || status=1; }; done < "$PROJECTS"
    exit $status ;;
  install)
    every="${2:-30}"
    unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    mkdir -p "$unit"
    cat > "$unit/pm-agent.service" <<EOF
[Unit]
Description=pm agent pass over registered projects

[Service]
Type=oneshot
ExecStart=$SELF run
Environment=PATH=$PATH
EOF
    cat > "$unit/pm-agent.timer" <<EOF
[Unit]
Description=Run pm agent passes every $every minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=${every}min
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload && systemctl --user enable --now pm-agent.timer
    systemctl --user list-timers pm-agent.timer --no-pager ;;
  uninstall)
    systemctl --user disable --now pm-agent.timer 2>/dev/null
    rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/pm-agent."{service,timer}
    systemctl --user daemon-reload; echo "timer removed" ;;
  logs)
    if [ -n "${2:-}" ]; then tail -f "$LOG_DIR/$(slug "$2")-latest.log"
    else ls -t "$LOG_DIR" | head -10; fi ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
