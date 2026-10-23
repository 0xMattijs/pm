---
name: sync-workflow
description: Update a project created by /pm:new-project to the latest pm templates (agent team, workflow rules, hooks, CI, stack layers) using Copier's three-way merge. Use when the user says "sync the workflow", "update the template", or "pull in pm changes".
---

# Sync the workflow

The scripts are in `<pm>/scripts/`. This skill's base directory is
`<pm>/skills/sync-workflow`.

1. **Preconditions.** Confirm that the current directory has
   `.copier-answers.base.yml` and that the working tree is clean. If it's not
   clean, ask the user whether to commit or stash first.
2. **Branch.** Run `git switch -c chore/sync-workflow`.
3. **Update.** Run `<pm>/scripts/sync.sh`. It updates the base layer first,
   then each stack layer, with one commit per layer. Exit code 2 means a
   layer has conflict markers.
4. **Resolve conflicts.** Keep project-specific changes, and take the
   template's structural changes. If a resolution isn't obvious, show the
   user both sides and ask. Commit the resolution, then rerun `sync.sh` to
   finish the remaining layers.
5. **Verify.** Run `scripts/check.sh` and `scripts/task.py phases`.
6. **Report.** Summarize what changed (`git diff main --stat`), grouped as
   agents, skills, workflow rules, hooks, and CI. Then offer to push and open
   a PR.

To add a stack layer to an existing project, run
`<pm>/scripts/scaffold.sh pre <layer> . <path>`, then
`<pm>/scripts/apply-layer.sh . <layer> path=<path>`, then
`<pm>/scripts/scaffold.sh post <layer> . <path>` on the sync branch.
