Unattended agent run. Follow `.claude/WORKFLOW.md`, section "Unattended runs".
Nobody can answer questions during this run.

1. Read open issues labelled `needs-human`. Apply each human answer, then close
   the issue with a comment that starts with `<!-- agent -->`.
2. Unless the mode is `execute`: run /babysit-pr once on each open wave PR,
   bottom of the stack first.
3. Unless the mode is `babysit`: run /execute-phase with the phase and flags
   given below, if any.
4. After 4.5 hours, start no new waves. Finish the current gate, commit the
   tracker changes, and push every wave branch you touched.
5. End with a summary of at most 10 lines: PRs opened or updated, tasks done,
   blocked items, and needs-human issues opened.
