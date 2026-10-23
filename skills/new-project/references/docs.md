# Planning documents

Write each document from the approved brief. Keep them short: agents read
them often, and every line costs context. Where the brief is silent, write
"TBD", not filler.

## docs/VISION.md

```markdown
# <Name>: vision

## Problem
<2-3 sentences: who hurts, how, today.>

## Users
<Primary user. Secondary users, if any.>

## Long-term goal (1-3 years)
<What success looks like.>

## Success signals
- <measurable signal>

## Principles
- <decision rule, e.g. "offline first", "no account needed to try it">

## Non-goals
- <what this will never do>
```

## docs/MVP.md

```markdown
# MVP

## Hypothesis
We believe <users> will <behavior> because <reason>.
We'll know when <signal>.

## Core journey
1. <step>

## Must-haves
| # | Capability | Acceptance criteria |
|---|---|---|
| M1 | <capability> | Given ..., when ..., then ... |

## Deliberately manual or faked
- <shortcut and when it gets replaced>

## Out of scope (later)
- <feature> -> <milestone in ROADMAP>

## Done when
- All must-have criteria pass in the deployed build.
- <hypothesis signal can be measured>
```

## ROADMAP.md

The roadmap holds order and scope only. Phase status comes from
`scripts/task.py phases`, so never write status here.

```markdown
# Roadmap

## Milestone 1: MVP
| Phase | Goal | Covers | Exit criteria |
|---|---|---|---|
| 01-foundation | <walking skeleton: deployed hello-world with CI, data store, and auth stub> | infra | <app deploys from main; check passes in CI> |
| 02-<slug> | <user-visible slice> | M1, M2 | <...> |

## Milestone 2: <name>
| Phase | Goal |
|---|---|
| ... | ... |

## Later
- <idea>

## Parked
- <dropped idea>: <reason>
```

Phase rules:
- Phase 01 is always a walking skeleton. Every layer builds, deploys (or
  installs, for mobile), and passes CI, with the chosen infrastructure wired
  up end to end.
- Every later MVP phase is a vertical slice that a user can try, and covers
  one or more must-haves (M1, M2, ...). Every must-have belongs to exactly
  one phase.
- Aim for 3 to 6 MVP phases.

## docs/adr/0001-stack.md

```markdown
# 0001: Stack and infrastructure

Status: accepted · Date: <YYYY-MM-DD>

## Context
<requirements that drove the choice>

## Decision
| Concern | Choice | Why |
|---|---|---|
| <layer/path> | ... | ... |
| Database | ... | ... |
| Auth | ... | ... |
| Hosting / builds | ... | ... |

## Alternatives considered
- <option>: <why not>

## Consequences
<what this makes easy or hard>
```

## CLAUDE.md

The project owns this file, and templates never overwrite it. Keep it under
60 lines.

```markdown
# <Name>

<One-sentence description.> MVP scope: see @docs/MVP.md.

@.claude/WORKFLOW.md
@.claude/stacks/<layer>.md   # one line per layer

## Repo map
- `<path>/`: <layer and purpose>
- `docs/`: vision, MVP, phases, ADRs

## Commands
- Check everything: `scripts/check.sh`
- Run locally: <per layer>
- Tasks: `scripts/task.py ready`

## Project rules
- <only rules specific to this project: domain terms, data handling,
  integrations>
```
