#!/usr/bin/env bash
# PostToolUse hook: format and lint the edited file. Each stack layer adds a
# script to format.d/ that acts only on files it owns. A script that exits 2
# feeds its stderr back to Claude so lint errors get fixed in the same turn.
file=$(jq -r '.tool_input.file_path // empty')
[ -n "$file" ] && [ -f "$file" ] || exit 0

status=0
for f in "$(dirname "$0")"/format.d/*.sh; do
  [ -e "$f" ] || continue
  bash "$f" "$file"
  rc=$?
  [ $rc -eq 2 ] && status=2
done
exit $status
