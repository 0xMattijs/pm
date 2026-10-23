# Stack selection and scaffolding

## Choosing layers

Choose the fewest layers that meet the requirements. A single-stack repo uses
`path=.`. A multi-stack repo gives each stack its own directory, such as
`web/`, `api/`, `mobile/`, `ios/`, or `android/`. Never put two stacks at `.`.

| Need | Default layer | Choose instead when |
|---|---|---|
| Web app or site with UI | `ts-next` (Vercel) | none |
| Backend logic for a web app | Next.js route handlers and server actions in `ts-next` (no extra layer) | it needs a separate service, long-running jobs, or heavy compute |
| Separate API or service | `python-uv` for data, AI, or ML work or quick iteration | `go` for high-concurrency services or simple deploys; `rust` for performance- or safety-critical code |
| CLI tool | `go` (single static binary) | `rust` for performance; `python-uv` for data scripting |
| Mobile app, either platform | `expo` (shares TypeScript with a `ts-next` web layer) | `flutter` for a heavily custom or animated UI, or for desktop targets too |
| Deep platform integration (HealthKit, widgets, ARKit, CarPlay, heavy background or Bluetooth work, top performance) | `ios-swift` and/or `android-kotlin` | Expo with config plugins, if only one or two native APIs are needed |
| One mobile platform only, with a native feel | `ios-swift` or `android-kotlin` | none |

Respect the user's stated language preferences over these defaults.

For infrastructure such as the database, auth, payments, email, and AI, pick
one option per need and record it in the stack ADR. On Vercel, prefer
Marketplace integrations, and load the `vercel:marketplace` skill before you
recommend a provider. Don't provision anything during bootstrap. Phase 01
tasks do that.

## Scaffolding (steps 4.2 and 4.4)

`<pm>/scripts/scaffold.sh` owns the native scaffolder commands and the
post-template fix-ups for every layer. Template CI runs the same script, so
these commands are tested weekly against the latest upstream scaffolders.

```
<pm>/scripts/scaffold.sh pre  <layer> <dest> <path> <slug> <bundle_id>   # step 4.2
<pm>/scripts/scaffold.sh post <layer> <dest> <path> <slug> <bundle_id>   # step 4.4
```

What each layer gets:

| Layer | pre | post |
|---|---|---|
| python-uv | `uv init --package`, dev dependencies ruff, pyright, pytest | none |
| ts-next | `create-next-app` (App Router, Tailwind, Biome, src/), Vitest | Biome autofix |
| go | `go mod init`, `cmd/<slug>/main.go` and a test | none |
| rust | `cargo init` | none |
| expo | `create-expo-app`, Biome, jest-expo, bundle IDs in `app.json` | `pnpm install` (hoisted), Biome autofix |
| flutter | `flutter create` for iOS and Android | none |
| ios-swift | none; the template seeds the skeleton | `xcodegen generate` on macOS |
| android-kotlin | none; the template seeds the skeleton | `gradle wrapper`, if Gradle is installed |

Set `GH_OWNER` for the Go module path and `PYTHON_VERSION` to override 3.13.

If a scaffolder fails because its flags changed upstream, fix it in
`scaffold.sh` (check `--help`), commit the fix to the pm repo, and rerun.
Don't work around it by hand in the project. After `post`, run
`scripts/check.sh <layer>` and fix any problems before the first commit.
