#!/usr/bin/env python3
"""SubagentStop hook: an implementer or reviewer can't finish without
leaving its result in the tracker.

- implementer: task status must be review or blocked, and the latest note
  must be its own handoff rather than an earlier review verdict.
- reviewer: the latest note must be a REVIEW PASS, FAIL, or ESCALATE verdict.

The task ID comes from the agent's first prompt ("Implement task 01-03."),
or from its final message as a fallback. If no ID is found, or the hook has
already blocked once, the agent is allowed to stop, so a guard failure can
never trap an agent in a loop.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

TASK_ID = re.compile(r"\b(\d{2}-\d{2})\b")


def first_prompt(transcript):
    try:
        with open(os.path.expanduser(transcript)) as f:
            for line in f:
                entry = json.loads(line)
                if entry.get("type") != "user":
                    continue
                content = entry.get("message", {}).get("content", "")
                if isinstance(content, list):
                    content = " ".join(c.get("text", "") for c in content
                                       if isinstance(c, dict))
                return content
    except (OSError, ValueError):
        pass
    return ""


def block(reason):
    print(json.dumps({"decision": "block", "reason": reason}))
    sys.exit(0)


def main():
    event = json.load(sys.stdin)
    if event.get("stop_hook_active"):
        return
    agent = event.get("agent_type", "").split(":")[-1]
    if agent not in ("implementer", "reviewer"):
        return

    text = first_prompt(event.get("agent_transcript_path", "")) or ""
    m = TASK_ID.search(text) or TASK_ID.search(event.get("last_assistant_message") or "")
    if not m:
        return
    task_id = m.group(1)

    root = Path(os.environ.get("CLAUDE_PROJECT_DIR", event.get("cwd", ".")))
    r = subprocess.run([sys.executable, str(root / "scripts" / "task.py"), "show",
                        task_id, "--json"], cwd=root, text=True, capture_output=True)
    if r.returncode != 0:
        return
    task = json.loads(r.stdout)
    last = task["notes"][-1] if task["notes"] else ""

    if agent == "implementer":
        missing = []
        if task["status"] not in ("review", "blocked"):
            missing.append(f'scripts/task.py set {task_id} review  (or blocked, with a "BLOCKED: <question>" note)')
        if not last or last.startswith("REVIEW"):
            missing.append(f'scripts/task.py note {task_id} "<handoff: what changed, criteria-to-test map, deviations, follow-ups>"')
        if missing:
            block(f"Task {task_id} isn't handed off yet (status: {task['status']}). "
                  "Before stopping, run:\n" + "\n".join(missing))
    else:
        if not re.match(r"REVIEW (PASS|FAIL|ESCALATE)", last):
            block(f"Record your verdict for task {task_id} before stopping: "
                  f'scripts/task.py note {task_id} "REVIEW <PASS|FAIL|ESCALATE>: '
                  '<numbered findings tagged [actionable|nit|ambiguous]>".')


if __name__ == "__main__":
    main()
