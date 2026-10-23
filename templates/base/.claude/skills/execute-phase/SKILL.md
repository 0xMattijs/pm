---
name: execute-phase
description: Execute a planned phase wave by wave, with parallel implementer agents in worktrees, a review gate per task, and a PR at the end. Use when the user says "execute", "build phase 01", "continue", or "next wave".
---

# Execute a phase

You are the orchestrator. Keep your own context small: pass task IDs to
agents, read their short replies, and keep state in the tracker.

## Setup

1. Pick the phase: the first phase that `scripts/task.py phases` lists as
   `in-progress` or `planned`, unless the arguments name one. If it has no
   contracts, run `/plan-phase` first. If `scripts/task.py lint -p <NN>`
   fails, fix the contracts before you dispatch anything.
2. Switch to the phase branch, creating it from `main` if needed:
   `git switch phase/<NN-slug>` or `git switch -c phase/<NN-slug> main`.
3. Resume safely. Run `scripts/task.py list -p <NN>`. Reset tasks stuck in
   `doing` with no worktree to `todo`. Re-review tasks in `review`.

## Wave loop

Repeat until `scripts/task.py ready -p <NN>` is empty:

1. **Dispatch.** For each ready task, spawn an `implementer` with
   `isolation: "worktree"` and the prompt `Implement task <id>.` Send all the
   spawns for a wave in one message so they run in parallel. Cap a wave at 4
   agents. Leave any extra tasks for the next round.
2. **Gate each result** as it returns:
   1. Spawn a `reviewer` with the task ID and the worktree branch range
      (`phase/<NN-slug>..<branch>`).
   2. On PASS, merge the branch into the phase branch with `git merge --no-ff`,
      run `scripts/check.sh`, run `scripts/task.py set <id> done`, and remove
      the worktree.
   3. On FAIL, send the findings back to an implementer in the same worktree.
      After a second FAIL, run `scripts/task.py set <id> blocked` and report
      the task to the user.
3. **Handle merge conflicts.** A conflict means the wave split was wrong.
   Resolve trivial conflicts yourself. For anything else, mark the later task
   `todo` with a note and let it rerun on the merged base.
4. **Report the wave** in one line: done, blocked, and next.

Ask the user only about blocked tasks or contract changes. Don't ask between
healthy waves; keep going.

## Close the phase

1. Check the exit criteria in `PHASE.md` end to end. Run the app or the
   tests the criteria name, and use the `run` skill if it's available.
2. Spawn a `reviewer` on `main..phase/<NN-slug>` to check the whole phase
   for integration issues.
3. Push and open a PR:
   `gh pr create --base main --title "Phase <NN>: <goal>"`. Put the exit
   criteria checklist and the task list in the body.
4. Report the PR URL. If this phase completed a milestone, suggest `/replan`.
