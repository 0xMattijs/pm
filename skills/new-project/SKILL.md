---
name: new-project
description: Bootstrap a new project end to end. Interview the user for the long-term vision and the MVP, choose stack layers (web, backend, CLI, native or cross-platform mobile), scaffold from layered templates, install the collaborating agent team and workflow, and set up GitHub, CI, and deploy targets. Use when the user wants to start, create, bootstrap, or set up a new project or app.
---

# New project

You run the bootstrap. Be efficient: ask grouped questions, propose defaults,
and don't make the user repeat anything.

Paths: this skill's base directory is `<pm>/skills/new-project`, so the
scripts are in `<pm>/scripts/`. References are in `references/` next to this
file. Read each one when its step starts, not before.

## 1. Interview

Read `references/interview.md` and run it. The result is an approved brief
covering the problem, users, the long-term vision, the MVP hypothesis and
scope, constraints, and platform needs.

Don't move on until the user approves your one-screen summary of the brief.

## 2. Choose the stack

Read `references/stacks.md`. Propose layers and their paths with a one-line
reason each, plus key infrastructure: database, auth, hosting, and the mobile
build service. Ask the user to confirm, and offer the strongest alternative
as a second option.

Also settle, in one AskUserQuestion call:
- **Tracker:** `files` (default; tasks in `docs/phases/`) or `github`
  (tasks as issues).
- **Planning:** `native` (default) or `gsd` (hands off to GSD after
  bootstrap).
- **Name and location:** the slug (default from the project name) and the
  directory (default `~/projects/<slug>`). The directory must not exist, or
  must be empty.
- **Bundle ID**, for mobile layers. Default: `com.<owner>.<slug>`, with the
  owner taken from `gh api user -q .login`.

## 3. Preflight

Run `<pm>/scripts/preflight.sh <layers...>`. If a required tool is missing,
tell the user the install command and stop until it's fixed. Mention warnings
once and continue.

## 4. Scaffold

Order matters. Native scaffolders need an empty directory, and templates come
after them.

1. `mkdir -p <dest> && git -C <dest> init -b main`.
2. For each stack layer, run
   `<pm>/scripts/scaffold.sh pre <layer> <dest> <path> <slug> <bundle_id>`.
3. Apply the layers, base first:
   ```
   <pm>/scripts/apply-layer.sh <dest> base project_name="<Name>" project_slug=<slug> \
     project_description="<one line>" tracker=<files|github> planning=<native|gsd>
   <pm>/scripts/apply-layer.sh <dest> <layer> path=<path> [layer options]
   ```
4. For each stack layer, run
   `<pm>/scripts/scaffold.sh post <layer> <dest> <path> <slug> <bundle_id>`.

## 5. Write the plan and agent config

Read `references/docs.md` and write `docs/VISION.md`, `docs/MVP.md`,
`ROADMAP.md`, `docs/adr/0001-stack.md`, and `CLAUDE.md` from the approved
brief. Write `.github/dependabot.yml` for exactly the ecosystems in use, plus
`github-actions`.

Then verify:
- `scripts/check.sh` passes. Fix failures; they're usually missing dev
  dependencies or formatting.
- `scripts/task.py phases` runs.
- `git add -A && git commit -m "chore: bootstrap <slug>"`.

## 6. External setup

These steps are outward-facing. Show the plan as a short list (repo name and
visibility, settings, secrets, deploy links) and get a yes before you run
anything.

1. `cd <dest> && <pm>/scripts/github-setup.sh <slug> "<description>" private`.
   Report any WARN or TODO lines to the user exactly as printed.
2. For `ts-next` with Vercel: if the `vercel` CLI is present and logged in, run
   `vercel link --yes --project <slug>` and `vercel git connect` in the layer
   path. Otherwise tell the user to run `! npm i -g vercel && vercel login`,
   and offer to continue once it's done.
3. For `expo` with EAS: if `eas` is logged in, run `eas init --non-interactive`
   and `eas build:configure -p all` in the layer path, then commit
   `app.json` and `eas.json`. Otherwise give the user the commands.
4. Push any commits made in this step.

## 7. Hand off

- With `planning: gsd`: run `/gsd-ingest-docs` in the new project so GSD
  imports VISION, MVP, and ROADMAP.
- Otherwise, tell the user to open the project
  (`cd <dest> && claude`) and run `/plan-phase` to plan phase 01.

End with a short summary: the path, repo URL, layers, MVP phases, open TODOs
(secrets, logins), and the next command. Keep it under 15 lines.
