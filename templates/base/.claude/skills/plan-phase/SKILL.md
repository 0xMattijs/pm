---
name: plan-phase
description: Plan the next (or a given) ROADMAP phase into PHASE.md and task contracts using the planner agent. Use when the user says "plan the next phase", "plan phase 02", or when /execute-phase finds no contracts.
---

# Plan a phase

1. **Pick the phase.** Use the phase from the arguments if one is given.
   Otherwise use the first phase in `ROADMAP.md` order that
   `scripts/task.py phases` doesn't list, or lists as `unplanned`. Create
   `docs/phases/<NN-slug>/` if it doesn't exist.
2. **Clear up gray areas, briefly.** Read the phase entry and `docs/MVP.md`.
   If two or more decisions would change the task breakdown, such as a data
   model choice, an auth approach, or a UX flow, ask the user about them in a
   single AskUserQuestion call. Skip this step when nothing is ambiguous.
   With `--chained` (run by `/execute-phase` without the user present), don't
   ask. Have the planner choose the simplest option that fits `VISION.md`
   and the ADRs, and record each choice under "Decisions" in `PHASE.md`.
   Stop and ask only if a decision would contradict `VISION.md` or
   `MVP.md`, or would add a new external service or a new stack layer.
3. **Delegate.** Spawn the `planner` agent with the phase number, the user's
   answers, and nothing else. It reads the documents itself.
4. **Check the plan.** Run `scripts/task.py lint -p <NN>`. It catches missing
   criteria, Owns lines, and test plans, bad dependencies, and file conflicts
   within a wave. Then confirm the judgment calls the lint can't make:
   - every exit criterion is covered by at least one task;
   - no task is too big. Send anything that looks like more than one
     session back to the planner to split.
   Send lint problems and gaps back to the planner, at most twice.
5. **Record it.** Don't commit the plan by hand. `scripts/waves.py ship`
   carries `docs/phases/<NN-slug>/` into the phase's first wave PR. Don't
   write status into `ROADMAP.md`. `scripts/task.py phases` derives it.
6. **Report.** Show the user the wave table from
   `scripts/task.py list -p <NN>` and any open questions. Offer to run
   `/execute-phase`. With `--chained`, report the wave count and the
   decisions in one or two lines, and return to the orchestrator.
