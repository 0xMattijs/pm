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
2. **Gate each result** as it returns. The agent that wrote the code never
   reviews it.
   1. Spawn a `reviewer` with the prompt
      `Review task <id>, range phase/<NN-slug>..<branch>.`
   2. On **PASS**, merge the branch into the phase branch with
      `git merge --no-ff`, run `scripts/check.sh`, run
      `scripts/task.py set <id> done`, and remove the worktree.
   3. On **FAIL**, run `scripts/task.py set <id> doing`, then send the task
      back to an implementer in the same worktree with the prompt
      `Fix review findings for task <id>.` It reads the findings from the
      tracker. Allow up to three review rounds per task. Stop early if a round
      repeats the previous round's actionable findings, because that loop
      isn't converging. When you stop, run `scripts/task.py set <id> blocked`
      and report the task to the user.
   4. On **ESCALATE**, run `scripts/task.py set <id> blocked` and put the
      ambiguous findings to the user in one AskUserQuestion call. Continue
      with the rest of the wave while you wait.
3. **Handle merge conflicts.** A conflict means the wave split was wrong.
   Resolve trivial conflicts yourself. For anything else, mark the later task
   `todo` with a note and let it rerun on the merged base.
4. **Report the wave** in one line: done, blocked, and next.

Ask the user only about blocked tasks or contract changes. Don't ask between
healthy waves; keep going.

## Close the phase

1. Watch the exit criteria pass. Run the app and the commands that
   `PHASE.md` names, using the `run` skill if it's available. For UI
   criteria, capture screenshots into `.evidence/phase-<NN>/`. Don't
   reason about whether the criteria hold; observe it.
2. Spawn a `reviewer` on `main..phase/<NN-slug>` to check the whole phase
   for integration issues.
3. Push and open a PR:
   `gh pr create --base main --title "Phase <NN>: <goal>"`. The body
   includes the exit criteria checklist, the task list, the observed Verify
   output, and a "How to verify" section with commands and expected output,
   so a human can watch it work in a minute.
4. Run `/babysit-pr` until the PR is green and has no open actionable
   comments. The risk gate labels the PR. Only a human adds `automerge`.
5. Report the PR URL and its risk label. If this phase completed a milestone,
   suggest `/replan`.
