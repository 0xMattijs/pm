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

## Native scaffolders (step 4.2)

Run these from `<dest>`. Replace `<p>` with the layer path. Each scaffolder
can change its flags over time, so check `--help` once if a command fails,
then adapt it.

**python-uv**
```
uv init --package --vcs none --python <ver> --name <slug> <p>
cd <p> && uv add --dev ruff pyright pytest
```

**ts-next** (the directory must be empty except for `.git`)
```
pnpm create next-app@latest <p> --ts --app --src-dir --tailwind --biome \
  --import-alias "@/*" --use-pnpm --disable-git --yes
cd <p> && pnpm add -D vitest @vitejs/plugin-react jsdom @testing-library/react
```
Then add `"test": "vitest run --passWithNoTests"` to `package.json` scripts.

**go**
```
mkdir -p <p>/cmd/<slug> && cd <p> && go mod init github.com/<owner>/<slug>
```
Write a minimal `cmd/<slug>/main.go` and one test.

**rust**
```
cargo init --vcs none --name <slug> <p>
```

**expo**
```
pnpm create expo-app@latest <p> --template default --yes
cd <p> && pnpm add -D @biomejs/biome && pnpm exec biome init
npx expo install jest-expo jest @testing-library/react-native -- -D
```
Set `expo.ios.bundleIdentifier` and `expo.android.package` in `app.json` to
the bundle ID. Add the `"jest": {"preset": "jest-expo"}` config and a
`"test": "jest --passWithNoTests"` script.

**flutter**
```
flutter create --org <bundle id minus last segment> --project-name <slug_snake> \
  --platforms ios,android <p>
```

**ios-swift and android-kotlin:** there's no scaffolder. The template seeds
the app skeleton.

## Post-template steps (step 4.4)

- **ts-next:** run `pnpm exec biome check --write .` once, so generated
  files match the lint rules.
- **expo:** run `pnpm install` (this picks up `.npmrc` hoisting), then
  `pnpm exec biome check --write .`.
- **ios-swift:** on macOS, run `xcodegen generate` in `<p>` and build once.
  On Linux, skip this; CI covers it.
- **android-kotlin:** if `gradle` is installed, run
  `cd <p> && gradle wrapper --gradle-version 8.14.3` and commit the wrapper.
  Otherwise, note in the summary that CI uses a provisioned Gradle until the
  wrapper is added.
- **All layers:** run `scripts/check.sh <layer>` and fix problems before the
  first commit.
