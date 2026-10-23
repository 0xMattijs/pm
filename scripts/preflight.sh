#!/usr/bin/env bash
# Check the tools a set of layers needs. Usage: preflight.sh <layer...>
# Exit 1 if a required tool is missing. Warnings don't fail.
missing=0
need() { command -v "$1" >/dev/null || { echo "MISSING $1  -> $2"; missing=1; }; }
want() { command -v "$1" >/dev/null || echo "warn    $1 not found ($2)"; }

need git "install git"
need gh "https://cli.github.com"
need uv "curl -LsSf https://astral.sh/uv/install.sh | sh"
need jq "apt install jq / brew install jq"
need python3 "install Python 3"
gh auth status >/dev/null 2>&1 || { echo "MISSING gh login -> run: gh auth login"; missing=1; }

for layer in "$@"; do
  case "$layer" in
    python-uv) ;;
    ts-next) need node "nvm install 24"; need pnpm "corepack enable pnpm"
             want vercel "npm i -g vercel; needed to link Vercel" ;;
    go) need go "https://go.dev/dl" ;;
    rust) need cargo "https://rustup.rs" ;;
    expo) need node "nvm install 24"; need pnpm "corepack enable pnpm"
          want eas "npm i -g eas-cli; needed for EAS builds" ;;
    flutter) need flutter "https://docs.flutter.dev/get-started/install" ;;
    ios-swift) if [ "$(uname)" = Darwin ]; then need xcodegen "brew install xcodegen"; need xcodebuild "install Xcode"
               else echo "info    ios-swift: not on macOS; local iOS builds are skipped and CI uses macOS runners"; fi ;;
    android-kotlin) want java "JDK 17+; local Android builds are skipped without it"
                    want gradle "needed once to generate the Gradle wrapper (sdk install gradle)"
                    [ -n "${ANDROID_HOME:-}" ] || echo "warn    ANDROID_HOME not set; local Android checks are skipped" ;;
    *) echo "unknown layer: $layer"; missing=1 ;;
  esac
done
[ $missing -eq 0 ] && echo "preflight ok"
exit $missing
