---
name: replan
description: Revisit VISION, MVP, and ROADMAP after a milestone or a plan-breaking finding, and record what changed and why. Use when the user says "replan", "MVP is done", "what's next", or when a phase reveals that the plan is wrong.
---

# Replan

1. **Gather facts.** Read `docs/VISION.md`, `docs/MVP.md`, `ROADMAP.md`, and
   recent ADRs. Run `scripts/task.py list -s blocked`, and collect follow-ups
   from the task handoff notes of the last milestone.
2. **Interview the user briefly.** Ask what they learned from using the
   result, what changed in priorities or constraints, and what to drop. Use
   AskUserQuestion for the choices and free text for the learnings.
3. **Update the documents.** Make each change in its source of truth:
   - Change `VISION.md` only if the long-term direction changed.
   - When the MVP is done, mark it shipped in `MVP.md` and define the next
     milestone the same way: hypothesis, scope, acceptance criteria.
   - In `ROADMAP.md`, re-cut and reorder the upcoming phases, and move
     dropped work to "Parked" with a reason. Keep the `Depends` column
     accurate, and make phases independent wherever you can: phases with no
     dependency on each other run at the same time.
4. **Record decisions.** Write one ADR in `docs/adr/` for each direction
   change.
5. **Commit and report.** Commit with `docs(plan): replan after <milestone>`,
   show the user the new roadmap, and offer `/plan-phase`.
