---
name: execute-phase
description: Execute planned phases wave by wave, with parallel implementer agents in worktrees, a review gate per task, and one small stacked PR per wave. Continues into the next phase of the milestone when a phase finishes cleanly. Use when the user says "execute", "build phase 01", "continue", or "next wave". Pass --once to stop after one phase.
---

# Execute a phase

You are the orchestrator. Keep your own context small: pass task IDs to
agents, read their short replies, and keep state in the tracker.

## Setup

Arguments: an optional phase number, and `--once` to stop after that phase
instead of chaining into the next one.

1. Pick the phase: the first phase that `scripts/task.py phases` lists as
   `in-progress` or `planned`, unless the arguments name one. If it has no
   contracts, run `/plan-phase` first. If `scripts/task.py lint -p <NN>`
   fails, fix the contracts before you dispatch anything.
2. Resume safely. Run `scripts/task.py list -p <NN>` and `gh pr list --search
   "head:wave/<NN>-"`. Reset tasks stuck in `doing` with no worktree to
   `todo`. Re-review tasks in `review`. Continue on the highest open wave
   branch.

## Wave loop

Repeat until `scripts/task.py ready -p <NN>` is empty:

1. **Branch the wave.** Wave `<W>` gets the branch `wave/<NN>-<W>`. Cut it
   from `main` if every earlier wave PR has merged. Otherwise cut it from the
   previous wave's branch, so the PRs stack and you never wait on a human
   merge.
2. **Dispatch.** For each ready task, spawn an `implementer` with
   `isolation: "worktree"` and the prompt `Implement task <id>.` Send all the
   spawns for a wave in one message so they run in parallel. Cap a wave at 4
   agents. Leave any extra tasks for the next round.
3. **Gate each result** as it returns. The agent that wrote the code never
   reviews it.
   1. Spawn a `reviewer` with the prompt
      `Review task <id>, range wave/<NN>-<W>..<branch>.`
   2. On **PASS**, merge the task branch into the wave branch with
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
4. **Handle merge conflicts.** A conflict means the wave split was wrong.
   Resolve trivial conflicts yourself. For anything else, mark the later task
   `todo` with a note and let it rerun on the merged base.
5. **Ship the wave** once every task in it is `done` or `blocked`, and at
   least one is `done`:
   1. Run `scripts/check.sh` and
      `scripts/risk.py <base>..wave/<NN>-<W> --max-lines 800 --max-files 30`.
   2. Commit the tracker changes (`docs/phases/`) on the wave branch, then push.
   3. Open the PR:
      `gh pr create --base <base> --head wave/<NN>-<W> --title "Phase <NN> wave <W>: <summary>"`.
      Here `<base>` is `main` or the previous wave's branch. The body lists
      the tasks (with `Closes #` lines for the github tracker), the observed
      Verify output for each task, and a "How to verify" section with commands
      and expected output, so a human can watch it work in a minute.
   4. Don't wait for the merge. Move on to the next wave.
6. **Report the wave** in one line: tasks done and blocked, the PR URL, and
   the risk.

Ask the user only about blocked tasks, escalations, or contract changes.
Don't ask between healthy waves; keep going.

## Close the phase

1. Watch the exit criteria pass on top of the last wave branch. Run the app
   and the commands that `PHASE.md` names, using the `run` skill if it's
   available. For UI criteria, capture screenshots into
   `.evidence/phase-<NN>/`. Don't reason about whether the criteria hold;
   observe it.
2. Spawn a `reviewer` on `main..wave/<NN>-<last>` to check the phase as a
   whole for integration issues. Fix actionable findings as a last wave.
3. Run `/babysit-pr` on each open wave PR, starting from the bottom of the
   stack, until each is green with no open actionable comments.
4. Report the phase in a few lines: tasks done, the PR stack in merge order
   with each PR's risk label, and what the human has to do. For example:
   "Merge #12, then #13. Both are risk:low; add `automerge` to let them go."

## Chain to the next phase

Unless `--once` was passed, continue into the next phase when **all** of
these hold:

- Every task in the finished phase is `done`. None are blocked or escalated.
- The exit criteria passed when you observed them.
- The next phase in `ROADMAP.md` belongs to the same milestone.
- No more than 6 wave PRs are open and unmerged
  (`gh pr list --search "head:wave/" --state open`). A deeper stack is too
  much unreviewed work in flight, so wait for the human to merge.

If any check fails, stop and say which one. At a milestone boundary, suggest
`/replan`. A replan needs the human, so never chain across a milestone.

To chain:

1. Cut the next phase's first wave branch, `wave/<NN+1>-1`, from the top of
   the current stack (or from `main` if the whole stack has merged).
2. Run `/plan-phase <NN+1> --chained` on that branch. The plan commit then
   ships in the first wave PR, where the human sees its decisions.
3. If planning stops with a question, stop the chain and pass the question to
   the human. Otherwise, continue at the wave loop for the new phase.

Report every phase transition in one line, for example
`Phase 02 done (3 PRs, all risk:low) -> planning phase 03`, so the human can
follow along and interrupt.
