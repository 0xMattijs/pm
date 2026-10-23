# Interview

The goal is a brief that's complete enough to plan from, gathered in about
five rounds. Use AskUserQuestion when the answers are a choice, and plain
questions when they need description. Ask two to four questions per round.
After each answer, propose a sensible default for anything left unsaid
instead of asking again.

## Round 1: problem and users

- What problem does this solve, and for whom? Name a specific person or role.
- How do they handle it today, and what's painful about that?
- Why build this now? Is it a personal tool, a side project, a startup, or
  for a client or employer?

## Round 2: long-term vision (1 to 3 years)

- If this succeeds, what does it look like? Think about users, usage, and
  revenue, if there is any.
- Which measurable signals would show it's working?
- What will it deliberately never do? These are the non-goals.
- Are there later platforms or markets in view, such as mobile after web or
  teams after individuals?

## Round 3: MVP

The MVP is the smallest product that tests the riskiest assumption with real
users. It isn't version 1.0 with fewer features.

- What's the riskiest assumption? Turn it into a hypothesis: "We believe
  <users> will <behavior> because <reason>. We'll know when <signal>."
- What's the one core journey a user must complete? Describe it step by step.
- List the candidate features. For each one, ask whether the MVP fails
  without it. Anything that doesn't pass moves to a later milestone.
- What can be manual, faked, or hard-coded at first? Examples: an admin done
  by hand, a single tenant, seeded data, no settings page.
- What's the time box? Default: two to four weeks of agent-paced work.

Push back on scope. If the MVP has more than about five must-have features or
more than one core journey, propose a cut and explain it.

## Round 4: constraints and platform

Ask only what the earlier answers didn't settle:
- **Platforms:** web, iOS, Android, desktop, CLI, or API only. For mobile, ask
  whether it must be native or cross-platform is fine, which device features
  it needs (camera, location, push, background work, Bluetooth,
  HealthKit-style APIs, widgets), and whether it works offline.
- **Data:** what's stored, how sensitive it is (PII, health, payments), and
  any compliance needs such as GDPR.
- **Accounts and auth:** none, email, social, organizations, or roles.
- **Integrations:** payments, email, AI models, third-party APIs.
- **Real-time or scale needs**, if any. Default: modest scale, optimized
  for simplicity.
- **Preferences:** languages the user wants or wants to avoid, hosting and
  budget limits, and an existing design system or brand.

## Round 5: confirm

Write the brief as one screen with these headings: Problem · Users · Vision ·
Non-goals · MVP hypothesis · Core journey · MVP must-haves · Later ·
Constraints · Platforms. Ask: "Is this right? What would you change?" Revise
the brief until the user approves it.
