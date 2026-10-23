#!/usr/bin/env python3
"""Task tracker CLI. The single interface agents use for task state.

Backend comes from `tracker:` in .copier-answers.base.yml:
  files  -> docs/phases/<NN-slug>/T<NN>-<slug>.md with frontmatter
  github -> GitHub issues labelled task, phase:<NN>, wave:<N>, status:<s>

Task IDs are "<phase>-<task>", for example 01-03. Both backends accept the
same commands:

  task.py phases                      list phases with status derived from tasks
  task.py lint [-p 01]                check contracts: criteria, scope, wave conflicts
  task.py list [-p 01] [-s todo]      list tasks
  task.py ready [-p 01] [--slots]     startable tasks: dependencies done, phase
                                      dependencies done, no file overlap with
                                      running tasks (--slots: cap at free agents)
  task.py next-phases                 unplanned phases of the current milestone
                                      whose phase dependencies are done
  task.py config max_agents           read .claude/pm.json
  task.py show 01-03 [--json]         print a task contract (json: status and notes)
  task.py new -p 01 -t "Title" [-w 1] [-d 01-01,01-02] < body.md
  task.py set 01-03 doing             change status
  task.py note 01-03 "text"           append a handoff note
  task.py init                        create GitHub labels (github backend)
"""

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

STATUSES = ["todo", "doing", "review", "done", "blocked"]
ROOT = Path(__file__).resolve().parent.parent


def main_checkout(root):
    """Tracker files live in the main checkout, shared by every worktree.

    Implementers run in git worktrees. If each one wrote status into its own
    copy of docs/phases/, the orchestrator would never see the change.
    """
    r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                       cwd=root, text=True, capture_output=True)
    if r.returncode == 0 and r.stdout.strip().endswith("/.git"):
        return Path(r.stdout.strip()).parent
    return root


PHASES = main_checkout(ROOT) / "docs" / "phases"


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:48]


def tracker_kind():
    answers = ROOT / ".copier-answers.base.yml"
    if answers.exists():
        m = re.search(r"^tracker:\s*(\w+)", answers.read_text(), re.M)
        if m:
            return m.group(1)
    return "files"


def phase_dir(phase):
    matches = sorted(PHASES.glob(f"{phase}-*")) if PHASES.exists() else []
    if not matches:
        sys.exit(f"phase {phase} not found under docs/phases/ (create it with /plan-phase)")
    return matches[0]


def split_deps(value):
    return [d.strip() for d in value.split(",") if d.strip()]


# --- files backend -----------------------------------------------------------

class FilesBackend:
    def _parse(self, path):
        text = path.read_text()
        m = re.match(r"---\n(.*?)\n---\n?(.*)", text, re.S)
        meta, body = {}, text
        if m:
            for line in m.group(1).splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    meta[k.strip()] = v.strip()
            body = m.group(2)
        return {
            "id": meta.get("id", ""),
            "title": meta.get("title", ""),
            "status": meta.get("status", "todo"),
            "wave": meta.get("wave", "1"),
            "depends": split_deps(meta.get("depends", "")),
            "phase": meta.get("id", "-").split("-")[0],
            "path": path,
            "body": body,
        }

    def _write(self, t):
        front = (
            f"---\nid: {t['id']}\ntitle: {t['title']}\nstatus: {t['status']}\n"
            f"wave: {t['wave']}\ndepends: {', '.join(t['depends'])}\n---\n"
        )
        t["path"].write_text(front + t["body"])

    def all(self):
        if not PHASES.exists():
            return []
        return [self._parse(p) for p in sorted(PHASES.glob("*/T*.md"))]

    def get(self, task_id):
        for t in self.all():
            if t["id"] == task_id:
                return t
        sys.exit(f"task {task_id} not found")

    def new(self, phase, title, wave, depends, body):
        d = phase_dir(phase)
        n = len(list(d.glob("T*.md"))) + 1
        task_id = f"{phase}-{n:02d}"
        t = {"id": task_id, "title": title, "status": "todo", "wave": wave,
             "depends": depends, "path": d / f"T{n:02d}-{slugify(title)}.md",
             "body": body.rstrip() + "\n\n## Log\n"}
        self._write(t)
        return task_id

    def set(self, task_id, status):
        t = self.get(task_id)
        t["status"] = status
        self._write(t)

    def note(self, task_id, text):
        t = self.get(task_id)
        if "## Log" not in t["body"]:
            t["body"] = t["body"].rstrip() + "\n\n## Log\n"
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M")
        t["body"] = t["body"].rstrip() + f"\n- {stamp}: {text}\n"
        self._write(t)

    def notes(self, task_id):
        log = self.get(task_id)["body"].split("## Log", 1)
        if len(log) < 2:
            return []
        return [m.group(1) for m in re.finditer(r"^- [\d-]+ [\d:]+: (.*)$", log[1], re.M)]

    def location(self, t):
        return str(t["path"].relative_to(PHASES.parent.parent))


# --- github backend ----------------------------------------------------------

class GithubBackend:
    def _gh(self, *args, capture=True):
        r = subprocess.run(["gh", *args], cwd=ROOT, text=True,
                           capture_output=capture)
        if r.returncode != 0:
            sys.exit(f"gh {' '.join(args)} failed: {r.stderr.strip()}")
        return r.stdout

    def _from_issue(self, issue):
        labels = [l["name"] for l in issue["labels"]]
        label = lambda prefix, default: next(
            (l.split(":", 1)[1] for l in labels if l.startswith(prefix)), default)
        m = re.match(r"\[(\d+-\d+)\]\s*(.*)", issue["title"])
        body = issue.get("body") or ""
        deps = re.search(r"^Depends:\s*(.*)$", body, re.M)
        return {
            "id": m.group(1) if m else "",
            "title": m.group(2) if m else issue["title"],
            "status": label("status:", "todo"),
            "wave": label("wave:", "1"),
            "depends": split_deps(deps.group(1)) if deps else [],
            "phase": label("phase:", ""),
            "number": issue["number"],
            "url": issue.get("url", ""),
            "body": body,
        }

    def all(self):
        out = self._gh("issue", "list", "--label", "task", "--state", "all",
                       "--limit", "1000", "--json", "number,title,labels,body,url")
        tasks = [self._from_issue(i) for i in json.loads(out)]
        return sorted((t for t in tasks if t["id"]), key=lambda t: t["id"])

    def get(self, task_id):
        for t in self.all():
            if t["id"] == task_id:
                return t
        sys.exit(f"task {task_id} not found")

    def _ensure_label(self, name, color="ededed"):
        subprocess.run(["gh", "label", "create", name, "--color", color, "--force"],
                       cwd=ROOT, capture_output=True)

    def init(self):
        self._ensure_label("task", "1d76db")
        for s, c in zip(STATUSES, ["ededed", "fbca04", "5319e7", "0e8a16", "d93f0b"]):
            self._ensure_label(f"status:{s}", c)

    def new(self, phase, title, wave, depends, body):
        existing = [t for t in self.all() if t["phase"] == phase]
        task_id = f"{phase}-{len(existing) + 1:02d}"
        self._ensure_label(f"phase:{phase}", "c5def5")
        self._ensure_label(f"wave:{wave}", "bfdadc")
        header = f"Depends: {', '.join(depends)}\n\n" if depends else ""
        self._gh("issue", "create", "--title", f"[{task_id}] {title}",
                 "--body", header + body,
                 "--label", f"task,phase:{phase},wave:{wave},status:todo")
        return task_id

    def set(self, task_id, status):
        t = self.get(task_id)
        n = str(t["number"])
        self._gh("issue", "edit", n, "--remove-label", f"status:{t['status']}",
                 "--add-label", f"status:{status}")
        if status == "done":
            self._gh("issue", "close", n)
        elif t["status"] == "done":
            self._gh("issue", "reopen", n)

    def note(self, task_id, text):
        self._gh("issue", "comment", str(self.get(task_id)["number"]), "--body", text)

    def notes(self, task_id):
        out = self._gh("issue", "view", str(self.get(task_id)["number"]),
                       "--json", "comments")
        return [c["body"] for c in json.loads(out)["comments"]]

    def location(self, t):
        return t["url"]


# --- commands ----------------------------------------------------------------

def config(key):
    """Project settings in .claude/pm.json, with defaults."""
    defaults = {"max_agents": 4, "max_open_wave_prs": 8}
    f = ROOT / ".claude" / "pm.json"
    try:
        data = json.loads(f.read_text()) if f.exists() else {}
    except ValueError:
        data = {}
    return {**defaults, **data}.get(key)


def roadmap():
    """ROADMAP.md phases in order: [{milestone, slug, phase, depends}].

    A table with a "Depends" column lists phase numbers there ("-" or empty
    means none). Without that column, each phase depends on the one before it.
    """
    f = PHASES.parent.parent / "ROADMAP.md"
    rows, milestone, dep_col = [], None, None
    for line in f.read_text().splitlines() if f.exists() else []:
        if line.startswith("## "):
            milestone, dep_col = line[3:].strip(), None
            continue
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells[0].lower() == "phase":
            dep_col = next((i for i, c in enumerate(cells) if c.lower().startswith("depend")), None)
            continue
        m = re.match(r"(\d{2})-[a-z0-9-]+$", cells[0])
        if not (m and milestone):
            continue
        if dep_col is None:
            deps = [rows[-1]["phase"]] if rows else []
        else:
            deps = re.findall(r"\b(\d{2})\b", cells[dep_col]) if dep_col < len(cells) else []
        rows.append({"milestone": milestone, "slug": cells[0], "phase": m.group(1), "depends": deps})
    return rows


def phase_states(tasks):
    by_phase = {}
    for t in tasks:
        by_phase.setdefault(t["phase"], []).append(t)
    return {p: phase_status(ts) for p, ts in by_phase.items()}


def ready(tasks, phase=None, limit=None):
    """Tasks that can start now, across phases unless one is given.

    A task is startable when its own dependencies are done, its phase's
    dependency phases are done, and none of the files it owns overlaps with a
    running task or with a task picked earlier in this call. Waves set the PR
    grouping and the preferred order, but they're not barriers.
    """
    status = {t["id"]: t["status"] for t in tasks}
    pstate = phase_states(tasks)
    pdeps = {r["phase"]: r["depends"] for r in roadmap()}
    taken = [p for t in tasks if t["status"] in ("doing", "review") for p in owned_paths(t["body"])]
    out = []
    for t in sorted(tasks, key=lambda t: (int(t["wave"]), t["phase"], t["id"])):
        if t["status"] != "todo" or (phase and t["phase"] != phase):
            continue
        if not all(status.get(d) == "done" for d in t["depends"]):
            continue
        if not all(pstate.get(d) == "done" for d in pdeps.get(t["phase"], [])):
            continue
        owns = owned_paths(t["body"])
        if any(overlaps(a, b) for a in owns for b in taken):
            continue
        out.append(t)
        taken += owns
        if limit is not None and len(out) >= limit:
            break
    return out


def next_phases(tasks):
    """Unplanned phases in the current milestone whose dependencies are done."""
    rows = roadmap()
    pstate = phase_states(tasks)
    current = next((r["milestone"] for r in rows if pstate.get(r["phase"]) != "done"), None)
    return [r for r in rows
            if r["milestone"] == current and r["phase"] not in pstate
            and all(pstate.get(d) == "done" for d in r["depends"])]


def chain_depth(tasks):
    """Length of the longest dependency chain among these tasks."""
    by_id = {t["id"]: t for t in tasks}
    memo = {}

    def depth(i):
        if i not in memo:
            memo[i] = 1 + max((depth(d) for d in by_id[i]["depends"] if d in by_id), default=0)
        return memo[i]

    return max((depth(i) for i in by_id), default=0)


def phase_status(tasks):
    """Phase status is derived from its tasks; nothing else stores it."""
    states = {t["status"] for t in tasks}
    if not tasks:
        return "unplanned"
    if states == {"done"}:
        return "done"
    if "blocked" in states:
        return "blocked"
    if states == {"todo"}:
        return "planned"
    return "in-progress"


def owned_paths(body):
    m = re.search(r"^- Owns:\s*(.*)$", body, re.M)
    if not m:
        return []
    return [p.strip(" `") for p in re.split(r",\s*", m.group(1)) if p.strip(" `")]


def overlaps(a, b):
    a, b = a.rstrip("/*"), b.rstrip("/*")
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def lint(tasks):
    """Return problems that would make a contract fail in execution."""
    problems = []
    ids = {t["id"] for t in tasks}
    for t in tasks:
        body = t["body"]
        crit = re.search(r"## Acceptance criteria\n(.*?)(\n## |\Z)", body, re.S)
        if not crit or not re.search(r"^- \[[ x]\]", crit.group(1), re.M):
            problems.append(f"{t['id']}: no acceptance criteria checklist")
        if not owned_paths(body):
            problems.append(f"{t['id']}: no '- Owns:' line under Scope")
        if "## Test plan" not in body:
            problems.append(f"{t['id']}: no test plan")
        if not re.search(r"## Verify\n\s*\S", body):
            problems.append(f"{t['id']}: no Verify steps (commands and expected output)")
        for d in t["depends"]:
            if d not in ids:
                problems.append(f"{t['id']}: depends on unknown task {d}")
        by_id = {x["id"]: x for x in tasks}
        for d in t["depends"]:
            if d in by_id and int(by_id[d]["wave"]) >= int(t["wave"]):
                problems.append(f"{t['id']}: depends on {d} in the same or a later wave")
    for ph in sorted({t["phase"] for t in tasks}):
        mine = [t for t in tasks if t["phase"] == ph]
        n, d = len(mine), chain_depth(mine)
        plan = next(iter(sorted(PHASES.glob(f"{ph}-*/PHASE.md"))), None)
        sequential = plan is not None and "Sequential:" in plan.read_text()
        if n >= 4 and d > n / 2 and not sequential:
            problems.append(
                f"phase {ph}: {n} tasks in a dependency chain of {d}, so at most "
                f"{max(1, n - d + 1)} run at once. Pin interfaces and stubs in wave 1 so "
                "more tasks run in parallel, or add 'Sequential: <reason>' to PHASE.md")
    open_tasks = [t for t in tasks if t["status"] != "done"]
    for i, a in enumerate(open_tasks):
        for b in open_tasks[i + 1:]:
            if a["phase"] != b["phase"] or a["wave"] != b["wave"]:
                continue
            for pa in owned_paths(a["body"]):
                for pb in owned_paths(b["body"]):
                    if overlaps(pa, pb):
                        problems.append(f"{a['id']} and {b['id']} (wave {a['wave']}) both own {pa}")
    return problems


def print_table(tasks):
    for t in tasks:
        deps = ",".join(t["depends"]) or "-"
        print(f"{t['id']}  {t['status']:<7} w{t['wave']}  deps:{deps:<12} {t['title']}")


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("phases")
    sub.add_parser("init")
    sp = sub.add_parser("lint")
    sp.add_argument("-p", "--phase")
    for name in ("list", "ready"):
        sp = sub.add_parser(name)
        sp.add_argument("-p", "--phase")
        if name == "list":
            sp.add_argument("-s", "--status", choices=STATUSES)
        else:
            sp.add_argument("--slots", action="store_true",
                            help="cap at max_agents minus running tasks")
    sub.add_parser("next-phases")
    sp = sub.add_parser("config")
    sp.add_argument("key")
    sp = sub.add_parser("show")
    sp.add_argument("id")
    sp.add_argument("--json", action="store_true")
    sp = sub.add_parser("new")
    sp.add_argument("-p", "--phase", required=True)
    sp.add_argument("-t", "--title", required=True)
    sp.add_argument("-w", "--wave", default="1")
    sp.add_argument("-d", "--depends", default="")
    sp = sub.add_parser("set")
    sp.add_argument("id")
    sp.add_argument("status", choices=STATUSES)
    sp = sub.add_parser("note")
    sp.add_argument("id")
    sp.add_argument("text")
    args = p.parse_args()

    backend = GithubBackend() if tracker_kind() == "github" else FilesBackend()

    if args.cmd == "init":
        if isinstance(backend, GithubBackend):
            backend.init()
        print("ok")
    elif args.cmd == "phases":
        tasks = backend.all()
        dirs = sorted(PHASES.glob("[0-9]*-*")) if PHASES.exists() else []
        for d in dirs:
            ph = d.name.split("-")[0]
            mine = [t for t in tasks if t["phase"] == ph]
            done = sum(t["status"] == "done" for t in mine)
            print(f"{d.name:<32} {phase_status(mine):<12} {done}/{len(mine)} done")
    elif args.cmd == "lint":
        tasks = [t for t in backend.all() if not args.phase or t["phase"] == args.phase]
        problems = lint(tasks)
        for p in problems:
            print(p)
        if problems:
            sys.exit(1)
        print(f"ok ({len(tasks)} tasks)")
    elif args.cmd == "list":
        tasks = [t for t in backend.all()
                 if (not args.phase or t["phase"] == args.phase)
                 and (not args.status or t["status"] == args.status)]
        print_table(tasks)
    elif args.cmd == "ready":
        tasks = backend.all()
        limit = None
        if args.slots:
            running = sum(t["status"] == "doing" for t in tasks)
            limit = max(0, config("max_agents") - running)
        print_table(ready(tasks, args.phase, limit))
    elif args.cmd == "next-phases":
        for r in next_phases(backend.all()):
            print(f"{r['slug']:<32} depends: {','.join(r['depends']) or '-'}")
    elif args.cmd == "config":
        print(config(args.key))
    elif args.cmd == "show":
        t = backend.get(args.id)
        if args.json:
            print(json.dumps({"id": t["id"], "status": t["status"],
                              "notes": backend.notes(args.id)}))
            return
        print(f"# [{t['id']}] {t['title']}")
        print(f"status: {t['status']}  wave: {t['wave']}  "
              f"depends: {', '.join(t['depends']) or '-'}  at: {backend.location(t)}\n")
        print(t["body"])
    elif args.cmd == "new":
        body = sys.stdin.read() if not sys.stdin.isatty() else ""
        print(backend.new(args.phase, args.title, args.wave,
                          split_deps(args.depends), body))
    elif args.cmd == "set":
        backend.set(args.id, args.status)
        print(f"{args.id} -> {args.status}")
    elif args.cmd == "note":
        backend.note(args.id, args.text)
        print("noted")


if __name__ == "__main__":
    main()
