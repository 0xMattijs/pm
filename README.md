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

## Template source and versions

Copier records the template source in each project. `PM_TEMPLATE_SRC`
selects it. It's set to `gh:0xMattijs/pm` in `~/.claude/settings.json`
(`env`), so projects sync from GitHub on any machine. Without the variable,
the local checkout (`~/projects/pm`) is used.

Projects bootstrap and sync from the **newest release tag**, not from `main`,
so only released, CI-tested templates reach them. A local source renders
`HEAD` instead, which is what `selftest.sh` uses. Set `PM_TEMPLATE_REF` to pin
a tag, or to `HEAD` to try unreleased changes in one project.

## Releasing

```sh
scripts/release.sh 0.3.0 --dry-run   # preview the changelog
scripts/release.sh 0.3.0
```

The script refuses unless you're on a clean `main` that matches `origin` and
template CI passed on that commit. It bumps the plugin version, prepends
`CHANGELOG.md` from Conventional Commits since the last tag, tags `v0.3.0`,
pushes, and creates a GitHub release. Then run `/pm:sync-workflow` in each
project.

Use semantic versions: patch for fixes, minor for new behavior, and major
when a sync needs manual steps. To undo a bad release, revert the change and
release a patch. Copier doesn't downgrade projects.

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

## Parallel execution

How many agents can work at once depends on the plan's width, so the system
pushes plans to be wide and dispatches as early as it safely can:

- **Plans for width.** The planner pins interfaces and stubs in wave 1, so
  later tasks build against them in parallel. `task.py lint` rejects a phase
  whose average parallelism (tasks divided by the longest dependency chain)
  is below 1.5, unless
  `PHASE.md` says `Sequential: <reason>`.
- **Dependency dispatch.** `task.py ready --slots` lists every task whose own
  dependencies and phase dependencies are done and whose files don't overlap
  a running task, capped at the free agent slots. Waves group PRs; they don't
  block.
- **Concurrent phases.** `ROADMAP.md` has a `Depends` column, and
  `task.py next-phases` lists every phase that can start, so independent
  phases run at the same time. Chaining never crosses a milestone.
- **Isolation.** `scripts/waves.py` gives each task its own worktree and
  branch, merges reviewed tasks into their wave, merges earlier waves forward,
  and ships stacked PRs. `waves.py pull-tracker` rebuilds task state in a
  fresh checkout.
- **Limits.** `.claude/pm.json` sets `max_agents` (default 4) and
  `max_open_wave_prs` (default 8). More agents use your usage limits faster.

`scripts/test-parallel.sh` tests all of this in a throwaway repo, and
template CI runs it.

## Scheduled agent runs

Agents keep working without an open session. The **local loop** is the main
scheduler, because it costs no GitHub Actions minutes:

```sh
ln -s ~/projects/pm/scripts/pm-agent.sh ~/.local/bin/pm-agent   # once
pm-agent add 0xMattijs/acme      # register a project
pm-agent install                 # systemd user timer, every 30 minutes
pm-agent list                    # last result per project
pm-agent logs 0xMattijs/acme     # follow the latest run
```

Each pass, per project:

1. **Clone.** Uses a dedicated clone in `~/.local/share/pm/agents/`, never
   your working copy, checked out at the top of the open wave stack.
2. **Precheck (no LLM).** `scripts/agent-precheck.py` checks for ready tasks,
   a phase in progress, an unplanned next phase in the current milestone,
   failing wave PRs, or answered `needs-human` issues. If there's nothing to
   do, the pass ends there.
3. **Agent.** Runs headless `claude -p` with `.claude/agent-run.md`: it
   applies answered questions, babysits the open wave PRs, and continues
   `/execute-phase` with chaining. Questions become `needs-human` issues. It
   can't merge or push to `main`. A lock prevents overlapping runs, and a
   timeout caps each run at 5 hours.

`claude -p` uses your Claude login, so it shares your plan's usage limits.
Put `ANTHROPIC_API_KEY=...` in `~/.config/pm/agent.env` to bill the API
instead. If the timer can't reach the keyring that holds your `gh` login, add
`GH_TOKEN=...` there too. The timer is persistent, so a pass missed while the
machine slept runs on wake.

**Fallback: GitHub Actions.** `.github/workflows/agent-run.yml` runs the same
pass on demand from the Actions tab, for when your machine is off. It needs
the `AGENT_GH_TOKEN` secret (a fine-grained token, so its pushes trigger CI)
and `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`. Its schedule is
commented out, because every scheduled run uses runner minutes even when it
has nothing to do.

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
