# Changelog

## v0.3.0 (2026-10-23)

### Added

- scale agents with width-first plans, dependency dispatch, and concurrent phases

### Fixed

- judge plan width by average parallelism

### Changed

- parallel execution

## v0.2.0 (2026-10-23)

First release of pm, a Claude Code plugin that bootstraps projects for agent-driven development.

### Added

- `/pm:new-project`: interview for the long-term vision and MVP, stack selection, scaffolding, agent setup, and GitHub, Vercel, and EAS configuration.
- Nine template layers: base, python-uv, ts-next, go, rust, expo, flutter, ios-swift, and android-kotlin. Each updates independently.
- Agent team (planner, implementer, reviewer, researcher) with `/plan-phase`, `/execute-phase`, `/babysit-pr`, and `/replan`.
- Contract-first vertical slices: task contracts with Verify steps, dependency waves, parallel worktrees, and one stacked PR per wave.
- One task tracker CLI over task files or GitHub issues, with contract lint and derived phase status.
- Guardrails: format hook, SubagentStop guard, review triage (actionable, nit, ambiguous), deterministic fail-closed risk gate, and label-gated auto-merge.
- Phase chaining within a milestone, with stop conditions.
- Unattended runs: a local agent loop (`pm-agent`, systemd timer) and an on-demand GitHub Actions fallback, with a no-LLM precheck and `needs-human` issues for questions.
- `/pm:sync-workflow`: three-way merge updates per layer.
- Template CI across all layers, weekly, and versioned releases (`scripts/release.sh`).

