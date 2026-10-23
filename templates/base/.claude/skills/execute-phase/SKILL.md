---
name: execute-phase
description: Execute planned phases with as many parallel implementer agents as the plan allows. Tasks start as soon as their dependencies are done, independent phases run at the same time, every task passes a review gate, and each wave ships as one small stacked PR. Continues into further phases of the milestone until something needs the human. Use when the user says "execute", "build phase 01", "continue", or "next wave". Pass --once to stop after the given phase.
---

# Execute phases

You are the orchestrator. Keep your own context small: pass task IDs to
agents, read their short replies, and keep state in the tracker.
`scripts/waves.py` handles branches and worktrees. Don't run those git
commands by hand.

## Setup

Arguments: an optional phase number, and `--once` to work only on that phase
and stop when it's done.

1. Run `scripts/task.py phases` and `scripts/task.py next-phases`. If a phase
   that has started has no contracts, or a phase is listed by `next-phases`,
   plan it with `/plan-phase <NN> --chained` (see "Start new phases" below).
   If `scripts/task.py lint` fails, fix the contracts before you dispatch.
2. Resume safely. Reset tasks stuck in `doing` whose worktree under
   `.claude/worktrees/task-<id>` is missing to `todo`. Send tasks in `review`
   to a reviewer again.
3. Read the agent cap with `scripts/task.py config max_agents`.

## Dispatch loop

Keep the agent slots full until no task can start and none is running:

1. **Find work.** `scripts/task.py ready --slots` (add `-p <NN>` with
   `--once`) lists the tasks that can start now. A task is startable when its
   own dependencies and its phase's dependency phases are done, and none of
   the files it owns overlaps a running task. Waves don't block. The list is
   already capped at the free agent slots.
2. **Dispatch.** For each listed task:
   `path=$(scripts/waves.py start <id>)`, then
   `scripts/task.py set <id> doing`. Then spawn an `implementer` with the
   prompt `Implement task <id>. Your worktree: <path>`. Send all spawns of a
   round in one message so they run in parallel.
3. **Gate each result** as it returns. Dispatch new work into the freed slot
   right away. Don't wait for the rest of the round. The agent that wrote the
   code never reviews it.
   1. Spawn a `reviewer` with the prompt
      `Review task <id>, range wave/<NN>-<W>..task/<id>. Worktree: <path>`.
   2. On **PASS**, run `scripts/waves.py merge <id>`. This merges the task
      into its wave branch, merges earlier waves forward, and runs
      `scripts/check.sh`.
      - Exit 0: run `scripts/task.py set <id> done`.
      - Exit 1 (checks failed after the merge, merge undone): treat it as
        FAIL, with the check output as the finding.
      - Exit 2 (conflict, merge aborted): the file ownership in the contracts
        was wrong. Note it on the task, set it to `todo`, delete the branch
        with `git worktree remove --force <path>` and
        `git branch -D task/<id>`, and let it rerun on the updated base.
   3. On **FAIL**, run `scripts/task.py set <id> doing`, then send the task
      back to an implementer: `Fix review findings for task <id>. Your
      worktree: <path>`. Allow up to three review rounds per task. Stop early
      if a round repeats the previous round's actionable findings. When you
      stop, run `scripts/task.py set <id> blocked` and tell the user.
   4. On **ESCALATE**, run `scripts/task.py set <id> blocked` and put the
      ambiguous findings to the user in one AskUserQuestion call. The other
      agents keep working while you wait.
4. **Ship each wave** when every task in it is `done` or `blocked` and at
   least one is `done`. Write a PR body to a temp file. List the tasks (with
   `Closes #` lines for the github tracker), the observed Verify output for
   each task, and a "How to verify" section with commands and expected output.
   Then run
   `scripts/waves.py ship <NN> <W> --title "Phase <NN> wave <W>: <summary>" --body-file <file>`.
   It commits tracker state, pushes, and opens the PR against the right base:
   the previous wave, the dependency phase's top wave, or `main`. Never wait
   for the merge.
5. **Report** each shipped wave in one line: tasks done and blocked, the PR
   URL, and the risk.

Ask the user only about blocked tasks, escalations, or contract changes.
Don't ask between healthy rounds; keep going. In an unattended run (see
"Unattended runs" in `.claude/WORKFLOW.md`), every question becomes a
`needs-human` issue instead of an AskUserQuestion call, and the run carries on
with other work.

## Close a phase

When every task of a phase is `done`:

1. Watch the exit criteria pass in the phase's top wave worktree
   (`.claude/worktrees/wave-<NN>-<last>`). Run the app and the commands
   `PHASE.md` names, using the `run` skill if it's available. For UI
   criteria, capture screenshots into `.evidence/phase-<NN>/`. Observe it;
   don't reason about it.
2. Spawn a `reviewer` on `main..wave/<NN>-<last>` to check the phase as a
   whole for integration issues. Ship any fixes as one more wave.
3. Run `/babysit-pr` on each open wave PR of the phase, bottom of the stack
   first.
4. Report the phase's PR stack in merge order, with risk labels, and what the
   human has to do. For example: "Merge #12, then #13. Both are risk:low;
   add `automerge` to let them go."

## Start new phases

Unless `--once` was passed, check `scripts/task.py next-phases` after each
phase closes, and also during the loop whenever the slots aren't full. It
lists unplanned phases of the current milestone whose dependency phases are
done. Several phases can be listed and run at the same time. Start a listed
phase only when **all** of these hold:

- No task is blocked or escalated in any phase it depends on.
- The exit criteria of its dependency phases passed when you observed them.
- Fewer than `max_open_wave_prs` (`scripts/task.py config max_open_wave_prs`)
  wave PRs are open. A deeper stack is too much unreviewed work in flight, so
  wait for the human to merge.
- `scripts/waves.py base <NN>` succeeds. Exit 3 means two or more dependency
  phases are still unmerged. The phase waits for the human to merge them.

To start one, run `/plan-phase <NN> --chained`. If planning stops with a
question, pass the question to the human and leave that phase. Otherwise its
tasks show up in `ready` on the next loop.

`next-phases` is empty at a milestone boundary. Stop there, and suggest
`/replan`. Crossing a milestone needs the human. Report each phase start in
one line, for example `Phase 02 done (3 PRs) -> starting 03 and 04 in parallel`.
