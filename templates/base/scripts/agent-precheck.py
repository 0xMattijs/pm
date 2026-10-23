#!/usr/bin/env python3
"""Decide, without an LLM, whether a scheduled agent run has work to do.

  agent-precheck.py [--max-open-waves N]

Prints `run=true|false` and `reason=...` lines (append them to
$GITHUB_OUTPUT in Actions). Work exists when any of these hold:

- an open wave PR has failing checks          -> babysit it
- a needs-human issue got a human answer      -> resume the blocked item
- a task can start (see task.py ready)          -> execute
- an unplanned phase of the current milestone has its dependencies done
                                                -> plan and execute

Execution counts only while fewer than max_open_wave_prs (.claude/pm.json)
wave PRs are open, and planning never crosses into a new milestone (that
needs /replan). If `gh` is unavailable, PR and issue checks are skipped with a note.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import task as tracker  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def sh(*args):
    r = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    return r.stdout if r.returncode == 0 else None


def gh_json(*args):
    out = sh("gh", *args)
    return json.loads(out) if out else None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--max-open-waves", type=int, default=None,
                   help="default: max_open_wave_prs in .claude/pm.json")
    args = p.parse_args()
    reasons, notes = [], []

    prs = gh_json("pr", "list", "--state", "open", "--search", "head:wave/",
                  "--json", "number,headRefName,statusCheckRollup")
    if prs is None:
        notes.append("gh unavailable: skipped PR checks")
        prs = []
    failing = [pr["number"] for pr in prs
               if any((c.get("conclusion") or "").upper() in ("FAILURE", "TIMED_OUT")
                      for c in pr.get("statusCheckRollup") or [])]
    if failing:
        reasons.append(f"failing wave PRs {failing}")

    issues = gh_json("issue", "list", "--label", "needs-human", "--state", "open",
                     "--json", "number,comments")
    if issues is None:
        notes.append("gh unavailable: skipped needs-human issues")
        issues = []
    answered = [i["number"] for i in issues
                if any(not c["author"]["login"].endswith("[bot]")
                       and "<!-- agent -->" not in c["body"]
                       for c in i.get("comments", []))]
    if answered:
        reasons.append(f"answered questions {answered}")

    limit = args.max_open_waves or tracker.config("max_open_wave_prs")
    if len(prs) >= limit:
        notes.append(f"{len(prs)} open wave PRs (limit {limit}): waiting for merges")
    else:
        tasks = tracker.backend().all()
        if tracker.ready(tasks):
            reasons.append("startable tasks")
        elif any(tracker.phase_status([t for t in tasks if t["phase"] == ph]) in ("in-progress", "planned")
                 for ph in {t["phase"] for t in tasks}):
            notes.append("phase in progress, but every open task is running or blocked")
        nxt = tracker.next_phases(tasks)
        if nxt:
            reasons.append("unplanned phases ready: " + ", ".join(r["slug"] for r in nxt))
        boundary = tracker.milestone_boundary(tasks)
        if boundary:
            notes.append(f"milestone boundary before {boundary['slug']}: run /replan")

    print(f"run={'true' if reasons else 'false'}")
    print(f"reason={'; '.join(reasons + notes) or 'nothing to do'}")


if __name__ == "__main__":
    main()
