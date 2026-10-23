# pm

A Claude Code plugin that bootstraps projects for agent-driven development.
`/pm:new-project` interviews you, writes the long-term vision and MVP plan,
picks stack layers, scaffolds the repo, installs a collaborating subagent
team, and sets up GitHub, CI, and deploy targets.

## Install

```sh
claude plugin marketplace add ~/projects/pm
claude plugin install pm@pm
```

Requirements: `git`, `gh` (logged in), `uv`, `jq`, and `python3`, plus each
stack's toolchain. `scripts/preflight.sh <layers...>` checks them.

## Commands

| Command | Does |
|---|---|
| `/pm:new-project` | Interview, plan, scaffold, configure agents, set up GitHub, Vercel, and EAS |
| `/pm:sync-workflow` | Pull template improvements into an existing project (three-way merge per layer) |

Inside a generated project:

| Command | Does |
|---|---|
| `/plan-phase` | `planner` turns the next roadmap phase into task contracts grouped in waves |
| `/execute-phase` | Parallel `implementer`s in worktrees, a `reviewer` gate per task, one stacked PR per wave. Chains into the next phase of the milestone until something needs you (`--once` for one phase) |
| `/replan` | Revisit vision, MVP, and roadmap after a milestone |

## Layers

| Layer | Stack | Local check needs |
|---|---|---|
| `base` | Agent team, workflow, task tracker, hooks, Claude GitHub Actions | — |
| `python-uv` | Python, uv, ruff, pyright, pytest | uv |
| `ts-next` | Next.js, pnpm, Biome, Vitest, Vercel | node, pnpm |
| `go` | Go, golangci-lint | go |
| `rust` | Cargo, clippy, rustfmt | cargo |
| `expo` | React Native (Expo Router), Biome, jest-expo, EAS | node, pnpm |
| `flutter` | Flutter, dart format, flutter analyze | flutter |
| `ios-swift` | SwiftUI, XcodeGen, Swift Testing | macOS with Xcode (otherwise CI only) |
| `android-kotlin` | Kotlin, Compose, Gradle version catalog | JDK and Android SDK (otherwise CI only) |

Each layer is applied separately and records its own
`.copier-answers.<layer>.yml`, so it updates independently. Layers own
disjoint files. The project owns `CLAUDE.md`, the planning docs, and the
mobile app skeletons, and updates never touch them.

## Repo layout

```
.claude-plugin/        plugin and marketplace manifests
skills/                /pm:new-project, /pm:sync-workflow
copier.yml             one template, layer chosen by the `layer` answer
templates/<layer>/     files rendered into projects
ignores/<layer>.txt    .gitignore rules each layer appends
scripts/               scaffold, apply-layer, sync, preflight, github-setup, selftest
.github/workflows/     template CI
```

## Template source

Copier records the template source in each project. `PM_TEMPLATE_SRC`
selects it. It's set to `gh:0xMattijs/pm` in `~/.claude/settings.json`
(`env`), so projects sync from GitHub on any machine. Push template changes
before you bootstrap or sync; `apply-layer.sh` warns about unpushed commits.
Without the variable, the local checkout (`~/projects/pm`) is used.
`selftest.sh` always tests the local checkout.

## Guardrails in generated projects

- **Format hook (PostToolUse).** Formats and lints each edited file. Lint
  errors that can't be fixed automatically go back to Claude in the same turn.
- **Subagent guard (SubagentStop).** An `implementer` can't stop until its task
  is in `review` or `blocked` and it has written a handoff note. A `reviewer`
  can't stop until it has recorded `REVIEW PASS` or `REVIEW FAIL`. The guard
  blocks once per stop, so it can't trap an agent in a loop.
- **Contract lint.** `scripts/task.py lint` rejects contracts that lack
  criteria, scope, a test plan, or Verify steps, that have bad dependencies,
  or whose wave has file conflicts.
- **Review by observation.** The reviewer runs on a different model from the
  implementer and reruns each contract's Verify commands. It tags findings
  `actionable`, `nit`, or `ambiguous`. Only actionable findings fail a task,
  ambiguous ones escalate to you, and the loop stops after three rounds.
- **Risk gate.** `scripts/risk.py` uses no LLM and fails closed. It checks
  size limits (400 lines per task, 800 per wave PR) and the sensitive paths
  and content patterns in `.claude/risk.txt`. `risk-gate.yml` labels every
  PR `risk:low` or `risk:high` with the reasons. Auto-merge needs your
  `automerge` label and low risk.
- **Small stacked PRs.** Each wave ships as one PR, stacked on the previous
  wave while that one is open, so agents never wait on a merge.
  `/babysit-pr` keeps each PR green.

## Scheduled agent runs

`.github/workflows/agent-run.yml` in each project runs the build loop in
GitHub Actions, so work continues without a local session. It runs every 3
hours once you set the repo variable `AGENT_RUNS_ENABLED=true`, or on demand
from the Actions tab.

1. **Precheck (no LLM).** `scripts/agent-precheck.py` checks for ready tasks,
   a phase in progress, an unplanned next phase in the current milestone,
   failing wave PRs, or answered `needs-human` issues. If there's nothing to
   do, the run ends there and costs nothing.
2. **Setup.** The run checks out the top of the open wave stack and installs
   toolchains through each layer's `scripts/setup.d/<layer>.sh`.
3. **Agent.** The run applies answered questions, runs `/babysit-pr` on the
   open wave PRs, then continues `/execute-phase` with chaining. Questions
   become `needs-human` issues. The agent can't merge or push to `main`.

Setup: the `AGENT_GH_TOKEN` secret (a fine-grained token for the repo, so
pushes trigger CI and the risk gate), plus `ANTHROPIC_API_KEY` (API billing,
no plan limits) or `CLAUDE_CODE_OAUTH_TOKEN` (shares your subscription
limits). `github-setup.sh` prints these steps.

The review practices follow
[PostHog's code review tips](https://posthog.com/newsletter/code-review-tips).

## Developing templates

Commit before testing: Copier renders from git `HEAD`. Then run the self-test
for the layer you changed:

```sh
scripts/selftest.sh go
```

`selftest.sh` bootstraps a throwaway project the same way `/pm:new-project`
does, using `scaffold.sh`, `apply-layer.sh`, and the stack's own scaffolder.
It then runs the stack checks, the tracker, both hooks, and a no-op sync.
`.github/workflows/templates.yml` runs it for every layer on each push and
PR, and weekly to catch upstream scaffolder changes. iOS runs on macOS.
