---
name: babysit-pr
description: Shepherd an open PR to mergeable. Watch CI, rerun flaky jobs once, fix real failures, act on review comments by triage, and keep the branch up to date. Use when the user says "babysit", "watch the PR", or "get this merged". Pair it with /loop for continuous watching.
---

# Babysit a PR

Use the PR from the arguments, or the PR for the current branch
(`gh pr view --json number,url`). Each pass does the following, then reports
in one line.

1. **Stay current.** If `gh pr view --json mergeStateStatus` reports
   `BEHIND`, merge the base branch in, run `scripts/check.sh`, and push. Never
   rebase or force-push a wave branch, because the PR above it in the stack
   builds on it. Hand real conflicts to the user. Don't guess at them.
2. **Check CI.** Run `gh pr checks`.
   - Pending: do nothing this pass.
   - Failed: read the log with `gh run view <id> --log-failed`. If the failure
     looks flaky (a timeout, a network error, or a test that passes locally),
     rerun it once with `gh run rerun <id> --failed`. If it fails again, or
     the failure is real, fix it on this branch, run `scripts/check.sh`, then
     commit and push.
3. **Handle review comments.** Read new comments with
   `gh pr view --comments` and `gh api repos/{owner}/{repo}/pulls/<n>/comments`.
   Triage each one:
   - **actionable:** fix it, push, and reply with the commit.
   - **nit:** fix it if it's trivial, otherwise reply with the reason. Then
     resolve it.
   - **ambiguous:** don't act on it. Collect it for the user. In an
     unattended run, open a `needs-human` issue for it.
   Run at most three fix rounds per PR. Stop early when a pass brings no new
   actionable comments.
4. **Respect the gates.** Never merge, and never add the `automerge` label
   yourself. If the risk gate says `risk:high`, list its reasons for the user.
5. **Done.** When checks are green, there are no open actionable comments,
   and only a human decision remains, tell the user exactly what's left.
   For example: "Ready. Risk low. Add `automerge` or merge."
