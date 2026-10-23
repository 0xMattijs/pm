#!/usr/bin/env python3
"""Branch and worktree mechanics for parallel task execution.

  waves.py base <phase>       branch that wave 1 of a phase starts from
  waves.py start <task-id>    prepare the task's worktree; prints its path
  waves.py merge <task-id>    merge a reviewed task into its wave branch
  waves.py ship <phase> <wave> --title T [--body-file F]
                              commit tracker state, push, open or update the PR

Layout. Each wave has a branch wave/<NN>-<W> checked out in a wave worktree,
.claude/worktrees/wave-<NN>-<W>. Each task has a branch task/<id> in
.claude/worktrees/task-<id>, cut from its wave branch. A wave branch starts
from the previous wave of its phase, or for wave 1 from the phase's base:
main, or the top wave of the one dependency phase that hasn't merged yet.
Earlier waves are merged forward into later ones, so a stacked PR always
contains everything below it.

Exit codes: 0 ok, 1 checks failed (merge undone), 2 merge conflict (merge
aborted), 3 the phase must wait (more than one dependency phase unmerged).
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import task as tracker  # noqa: E402

ROOT = tracker.main_checkout(tracker.ROOT)
TREES = ROOT / ".claude" / "worktrees"


def git(*args, cwd=ROOT, check=True):
    r = subprocess.run(["git", *args], cwd=cwd, text=True, capture_output=True)
    if check and r.returncode != 0:
        sys.exit(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r


def has_ref(ref):
    return git("rev-parse", "--verify", "--quiet", ref, check=False).returncode == 0


def local_branch(name):
    """Make sure a local branch exists, creating it from origin if needed."""
    if has_ref(f"refs/heads/{name}"):
        return True
    if has_ref(f"refs/remotes/origin/{name}"):
        git("branch", "--quiet", name, f"origin/{name}")
        return True
    return False


def waves_of(phase):
    names = set()
    for ref in ("refs/heads/wave", "refs/remotes/origin/wave"):
        out = git("for-each-ref", "--format=%(refname:short)", ref, check=False).stdout
        for line in out.split():
            m = re.search(rf"wave/{phase}-(\d+)$", line)
            if m:
                names.add(int(m.group(1)))
    return sorted(names)


def mainline():
    return "origin/main" if has_ref("refs/remotes/origin/main") else "main"


def merged(branch):
    return git("merge-base", "--is-ancestor", branch, mainline(), check=False).returncode == 0


def phase_base(phase):
    deps = next((r["depends"] for r in tracker.roadmap() if r["phase"] == phase), [])
    unmerged = []
    for d in deps:
        tops = waves_of(d)
        if tops:
            top = f"wave/{d}-{tops[-1]}"
            local_branch(top)
            if not merged(top):
                unmerged.append(top)
    if len(unmerged) > 1:
        print(f"phase {phase} waits: dependencies {', '.join(unmerged)} are all unmerged", file=sys.stderr)
        sys.exit(3)
    return unmerged[0] if unmerged else "main"


def prev_branch(phase, wave):
    earlier = [w for w in waves_of(phase) if w < wave]
    return f"wave/{phase}-{earlier[-1]}" if earlier else None


def wave_tree(phase, wave):
    """Wave worktree, creating the branch and worktree if needed."""
    name = f"wave/{phase}-{wave}"
    path = TREES / f"wave-{phase}-{wave}"
    if not local_branch(name):
        git("branch", "--quiet", name, prev_branch(phase, wave) or phase_base(phase))
    if not path.exists():
        TREES.mkdir(parents=True, exist_ok=True)
        git("worktree", "add", "--quiet", str(path), name)
    return name, path


def merge_into(path, ref, label):
    r = git("merge", "--no-ff", "--no-edit", ref, cwd=path, check=False)
    if r.returncode != 0:
        git("merge", "--abort", cwd=path, check=False)
        print(f"conflict merging {label} into {path.name}: {r.stdout.strip()[-400:]}", file=sys.stderr)
        sys.exit(2)


def forward(phase, wave, path):
    prev = prev_branch(phase, wave)
    if prev:
        local_branch(prev)
        if git("merge-base", "--is-ancestor", prev, "HEAD", cwd=path, check=False).returncode != 0:
            merge_into(path, prev, prev)


def cmd_start(task_id):
    t = tracker.FilesBackend().get(task_id) if tracker.tracker_kind() == "files" else tracker.GithubBackend().get(task_id)
    phase, wave = t["phase"], int(t["wave"])
    name, wpath = wave_tree(phase, wave)
    forward(phase, wave, wpath)
    tpath = TREES / f"task-{task_id}"
    if not tpath.exists():
        if has_ref(f"refs/heads/task/{task_id}"):
            git("worktree", "add", "--quiet", str(tpath), f"task/{task_id}")
        else:
            git("worktree", "add", "--quiet", "-b", f"task/{task_id}", str(tpath), name)
    print(tpath)


def cmd_merge(task_id):
    t = tracker.FilesBackend().get(task_id) if tracker.tracker_kind() == "files" else tracker.GithubBackend().get(task_id)
    phase, wave = t["phase"], int(t["wave"])
    _, wpath = wave_tree(phase, wave)
    forward(phase, wave, wpath)
    merge_into(wpath, f"task/{task_id}", f"task/{task_id}")
    check = subprocess.run(["bash", "scripts/check.sh"], cwd=wpath, text=True, capture_output=True)
    if check.returncode != 0:
        git("reset", "--hard", "--quiet", "ORIG_HEAD", cwd=wpath)
        print(f"checks failed after merging {task_id}; merge undone:\n{check.stdout[-1500:]}{check.stderr[-500:]}", file=sys.stderr)
        sys.exit(1)
    tpath = TREES / f"task-{task_id}"
    if tpath.exists():
        git("worktree", "remove", "--force", str(tpath))
    git("branch", "--quiet", "-D", f"task/{task_id}", check=False)
    print(f"merged {task_id} into wave/{phase}-{wave}")


def cmd_ship(phase, wave, title, body_file):
    name, wpath = wave_tree(phase, wave)
    forward(phase, wave, wpath)
    if tracker.tracker_kind() == "files":
        # Task state lives in the main checkout; carry this phase's files into the PR.
        for src in sorted(tracker.PHASES.glob(f"{phase}-*")):
            dst = wpath / "docs" / "phases" / src.name
            shutil.copytree(src, dst, dirs_exist_ok=True)
        git("add", "docs/phases", cwd=wpath)
        if git("diff", "--cached", "--quiet", cwd=wpath, check=False).returncode != 0:
            git("commit", "--quiet", "-m", f"chore(tracker): phase {phase} wave {wave} status", cwd=wpath)
    git("push", "--quiet", "-u", "origin", name, cwd=wpath)
    existing = subprocess.run(["gh", "pr", "view", name, "--json", "url", "-q", ".url"],
                              cwd=wpath, text=True, capture_output=True)
    if existing.returncode == 0 and existing.stdout.strip():
        print(existing.stdout.strip())
        return
    base = prev_branch(phase, wave) or phase_base(phase)
    args = ["gh", "pr", "create", "--base", base, "--head", name, "--title", title]
    args += ["--body-file", body_file] if body_file else ["--body", ""]
    r = subprocess.run(args, cwd=wpath, text=True, capture_output=True)
    if r.returncode != 0:
        sys.exit(f"gh pr create failed: {r.stderr.strip()}")
    print(r.stdout.strip())


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("base").add_argument("phase")
    sub.add_parser("start").add_argument("id")
    sub.add_parser("merge").add_argument("id")
    sp = sub.add_parser("ship")
    sp.add_argument("phase")
    sp.add_argument("wave", type=int)
    sp.add_argument("--title", required=True)
    sp.add_argument("--body-file")
    args = p.parse_args()
    if args.cmd == "base":
        print(phase_base(args.phase))
    elif args.cmd == "start":
        cmd_start(args.id)
    elif args.cmd == "merge":
        cmd_merge(args.id)
    elif args.cmd == "ship":
        cmd_ship(args.phase, args.wave, args.title, args.body_file)


if __name__ == "__main__":
    main()
