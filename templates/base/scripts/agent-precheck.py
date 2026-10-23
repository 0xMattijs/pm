#!/usr/bin/env python3
"""Decide, without an LLM, whether a scheduled agent run has work to do.

  agent-precheck.py [--max-open-waves 6]

Prints `run=true|false` and `reason=...` lines (append them to
$GITHUB_OUTPUT in Actions). Work exists when any of these hold:

- an open wave PR has failing checks          -> babysit it
- a needs-human issue got a human answer      -> resume the blocked item
- a task is ready, or a phase is in progress  -> execute
- the next ROADMAP phase in the current milestone is unplanned -> plan and execute

Execution counts only while fewer than --max-open-waves wave PRs are open,
and planning never crosses into a new milestone (that needs /replan). If
`gh` is unavailable, PR and issue checks are skipped with a note.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def sh(*args):
    r = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    return r.stdout if r.returncode == 0 else None


def gh_json(*args):
    out = sh("gh", *args)
    return json.loads(out) if out else None


def roadmap_phases():
    """[(milestone, phase-slug)] in ROADMAP order."""
    f = ROOT / "ROADMAP.md"
    milestone, out = None, []
    for line in f.read_text().splitlines() if f.exists() else []:
        if line.startswith("## "):
            milestone = line[3:].strip()
        m = re.match(r"\|\s*(\d{2}-[a-z0-9-]+)\s*\|", line)
        if m and milestone:
            out.append((milestone, m.group(1)))
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--max-open-waves", type=int, default=6)
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

    can_execute = len(prs) < args.max_open_waves
    if not can_execute:
        notes.append(f"{len(prs)} open wave PRs (limit {args.max_open_waves}): waiting for merges")
    else:
        task = [sys.executable, str(ROOT / "scripts" / "task.py")]
        ready = sh(*task, "ready") or ""
        phases = sh(*task, "phases") or ""
        if ready.strip():
            reasons.append("ready tasks")
        elif re.search(r"\b(in-progress|planned)\b", phases):
            reasons.append("phase in progress")
        else:
            planned = {line.split()[0] for line in phases.splitlines() if line.strip()}
            seq = roadmap_phases()
            done_idx = [i for i, (_, slug) in enumerate(seq) if slug in planned]
            nxt = (done_idx[-1] + 1) if done_idx else 0
            if nxt < len(seq):
                same_milestone = not done_idx or seq[nxt][0] == seq[done_idx[-1]][0]
                if same_milestone:
                    reasons.append(f"next phase {seq[nxt][1]} unplanned")
                else:
                    notes.append(f"milestone boundary before {seq[nxt][1]}: run /replan")

    print(f"run={'true' if reasons else 'false'}")
    print(f"reason={'; '.join(reasons + notes) or 'nothing to do'}")


if __name__ == "__main__":
    main()
