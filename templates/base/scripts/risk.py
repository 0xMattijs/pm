#!/usr/bin/env python3
"""Deterministic risk gate for a diff. No LLM involved, and it fails closed.

  risk.py <base>..<head> [--max-lines 400] [--max-files 20] [--json]

The result is "high" if the diff is too big, touches a path listed in
.claude/risk.txt, adds a line matching a listed content pattern, or can't be
computed. Otherwise it's "low". The exit code is 0 for low and 1 for high, so
scripts and CI can gate on it. Rules only make the gate stricter. Nothing in a
diff can lower the risk.
"""

import argparse
import fnmatch
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def rules():
    paths, content = [], []
    f = ROOT / ".claude" / "risk.txt"
    for line in f.read_text().splitlines() if f.exists() else []:
        line = line.strip()
        if line.startswith("path:"):
            paths.append(line[5:].strip())
        elif line.startswith("content:"):
            content.append(re.compile(line[8:].strip()))
    return paths, content


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, text=True,
                          capture_output=True, check=True).stdout


def assess(rng, max_lines, max_files):
    reasons = []
    try:
        numstat = git("diff", "--numstat", rng)
        added = git("diff", "--unified=0", "--no-color", rng)
    except subprocess.CalledProcessError as e:
        return "high", [f"could not compute diff for {rng}: {e.stderr.strip()}"], {}

    files, lines = [], 0
    for row in numstat.splitlines():
        a, d, path = row.split("\t", 2)
        files.append(path)
        lines += (int(a) if a != "-" else 0) + (int(d) if d != "-" else 0)
    if lines > max_lines:
        reasons.append(f"{lines} changed lines (limit {max_lines}); split it")
    if len(files) > max_files:
        reasons.append(f"{len(files)} files (limit {max_files}); split it")

    path_rules, content_rules = rules()
    for path in files:
        for pattern in path_rules:
            if fnmatch.fnmatch(path, pattern):
                reasons.append(f"sensitive path {path} (rule {pattern})")
                break

    current = None
    for line in added.splitlines():
        if line.startswith("+++ b/"):
            current = line[6:]
        elif line.startswith("+") and not line.startswith("+++"):
            for rx in content_rules:
                if rx.search(line):
                    reasons.append(f"sensitive content in {current} (rule {rx.pattern})")
    reasons = list(dict.fromkeys(reasons))
    return ("high" if reasons else "low"), reasons, {"lines": lines, "files": len(files)}


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("range")
    p.add_argument("--max-lines", type=int, default=400)
    p.add_argument("--max-files", type=int, default=20)
    p.add_argument("--json", action="store_true")
    args = p.parse_args()

    level, reasons, stats = assess(args.range, args.max_lines, args.max_files)
    if args.json:
        print(json.dumps({"risk": level, "reasons": reasons, **stats}))
    else:
        print(f"risk: {level}  ({stats.get('lines', '?')} lines, {stats.get('files', '?')} files)")
        for r in reasons:
            print(f"- {r}")
    sys.exit(0 if level == "low" else 1)


if __name__ == "__main__":
    main()
