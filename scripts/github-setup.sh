#!/usr/bin/env bash
# Create the GitHub repo and configure it for the agent workflow.
# Run from the project root after the first commit.
# Usage: github-setup.sh <slug> "<description>" [private|public]
# Reads CLAUDE_CODE_OAUTH_TOKEN and EXPO_TOKEN from the environment if set.
set -uo pipefail
slug="$1"; desc="$2"; visibility="${3:-private}"

step() { echo "== $*"; }
warn() { echo "WARN: $*" >&2; }

step "create repo ($visibility)"
gh repo create "$slug" "--$visibility" --description "$desc" --source . --remote origin --push || exit 1
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)

step "merge settings: squash only, delete merged branches, auto-merge"
gh repo edit "$repo" --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false \
  --delete-branch-on-merge --enable-auto-merge >/dev/null || warn "could not update merge settings"

step "protect main (ruleset)"
gh api -X POST "repos/$repo/rulesets" --input - >/dev/null 2>ruleset.err <<'JSON' || warn "ruleset not created (private repos need GitHub Pro or a paid org plan): $(cat ruleset.err)"
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": false,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false}}
  ]
}
JSON
rm -f ruleset.err

step "security: vulnerability alerts and automated fixes"
gh api -X PUT "repos/$repo/vulnerability-alerts" >/dev/null 2>&1 || warn "could not enable vulnerability alerts"
gh api -X PUT "repos/$repo/automated-security-fixes" >/dev/null 2>&1 || warn "could not enable automated security fixes"

step "secrets"
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  gh secret set CLAUDE_CODE_OAUTH_TOKEN -R "$repo" --body "$CLAUDE_CODE_OAUTH_TOKEN" && echo "set CLAUDE_CODE_OAUTH_TOKEN"
else
  echo "TODO: run 'claude setup-token', then: gh secret set CLAUDE_CODE_OAUTH_TOKEN -R $repo"
  echo "      and install the Claude GitHub app: https://github.com/apps/claude"
fi
if ls .copier-answers.expo.yml >/dev/null 2>&1; then
  if [ -n "${EXPO_TOKEN:-}" ]; then gh secret set EXPO_TOKEN -R "$repo" --body "$EXPO_TOKEN" && echo "set EXPO_TOKEN"
  else echo "TODO: create an Expo access token, then: gh secret set EXPO_TOKEN -R $repo"; fi
fi

if grep -q '^tracker: github' .copier-answers.base.yml 2>/dev/null; then
  step "tracker labels"
  python3 scripts/task.py init
fi

echo "repo: https://github.com/$repo"
