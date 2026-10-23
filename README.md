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
| `/execute-phase` | Parallel `implementer`s in worktrees, a `reviewer` gate per task, a PR per phase |
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
scripts/               apply-layer, sync, preflight, github-setup
```

## Template source

Copier records the template source in each project. By default it's this
checkout (`~/projects/pm`). To make syncing work on any machine, push this
repo and set `PM_TEMPLATE_SRC=gh:<owner>/pm` before bootstrapping.

## Developing templates

Commit before testing: Copier renders from git `HEAD`. Then try a change in
a scratch project:

```sh
d=$(mktemp -d) && git -C "$d" init -qb main
scripts/apply-layer.sh "$d" base project_name=Test
scripts/apply-layer.sh "$d" go path=cli
```
