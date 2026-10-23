#!/usr/bin/env bash
# Native scaffolding for a stack layer, run before (pre) and after (post) the
# layer's template. The bootstrap skill and the template CI both use it, so
# scaffolder flags live in exactly one place.
#
# Usage: scaffold.sh pre|post <layer> <dest> <path> [slug] [bundle_id]
set -euo pipefail
stage="$1"; layer="$2"; dest="$3"; p="$4"
slug="${5:-$(basename "$dest")}"; bundle="${6:-com.example.app}"
snake="${slug//-/_}"
cd "$dest"

pkg_script() {  # pkg_script <dir> <name> <command>
  node -e 'const f=process.argv[1]+"/package.json",fs=require("fs"),j=JSON.parse(fs.readFileSync(f));
           j.scripts={...j.scripts,[process.argv[2]]:process.argv[3]};fs.writeFileSync(f,JSON.stringify(j,null,2)+"\n")' "$1" "$2" "$3"
}

pnpm_lenient_builds() {  # pnpm_lenient_builds <dir>
  # pnpm 11 fails installs when it skips a dependency's build scripts. Keep
  # skipping them (the safe default) but warn instead of failing.
  local f="$1/pnpm-workspace.yaml"
  grep -qs '^strictDepBuilds:' "$f" || echo "strictDepBuilds: false" >> "$f"
}

case "$stage:$layer" in
  pre:python-uv)
    uv init --quiet --package --vcs none --python "${PYTHON_VERSION:-3.13}" --name "$slug" "$p"
    (cd "$p" && uv add --quiet --dev ruff pyright pytest)
    ;;
  pre:ts-next)
    pnpm create next-app@latest "$p" --ts --app --src-dir --tailwind --biome \
      --import-alias "@/*" --use-pnpm --disable-git --yes
    pnpm_lenient_builds "$p"
    (cd "$p" && pnpm add -D vitest @vitejs/plugin-react jsdom @testing-library/react)
    pkg_script "$p" test "vitest run --passWithNoTests"
    ;;
  pre:go)
    mkdir -p "$p/cmd/$slug"
    (cd "$p" && go mod init "github.com/${GH_OWNER:-example}/$slug" 2>/dev/null)
    printf 'package main\n\nimport "fmt"\n\nfunc main() {\n\tfmt.Println("%s")\n}\n' "$slug" > "$p/cmd/$slug/main.go"
    printf 'package main\n\nimport "testing"\n\nfunc TestMain(t *testing.T) {\n\tmain()\n}\n' > "$p/cmd/$slug/main_test.go"
    ;;
  pre:rust)
    cargo init --quiet --vcs none --name "$slug" "$p"
    ;;
  pre:expo)
    pnpm create expo-app@latest "$p" --template default --yes
    pnpm_lenient_builds "$p"
    # Replace the example app with Expo's minimal blank app ("n" = delete the
    # example instead of moving it to app-example/).
    if grep -q '"reset-project"' "$p/package.json"; then
      (cd "$p" && echo n | pnpm run --silent reset-project >/dev/null)
    fi
    (cd "$p" && pnpm add -D @biomejs/biome && pnpm exec biome init \
      && npx expo install jest-expo jest @testing-library/react-native -- -D)
    node -e 'const f=process.argv[1]+"/app.json",fs=require("fs"),j=JSON.parse(fs.readFileSync(f));
             j.expo.ios={...j.expo.ios,bundleIdentifier:process.argv[2]};
             j.expo.android={...j.expo.android,package:process.argv[2]};
             fs.writeFileSync(f,JSON.stringify(j,null,2)+"\n")' "$p" "$bundle"
    node -e 'const f=process.argv[1]+"/package.json",fs=require("fs"),j=JSON.parse(fs.readFileSync(f));
             j.jest={preset:"jest-expo"};fs.writeFileSync(f,JSON.stringify(j,null,2)+"\n")' "$p"
    pkg_script "$p" test "jest --passWithNoTests"
    ;;
  pre:flutter)
    flutter create --org "${bundle%.*}" --project-name "$snake" --platforms ios,android "$p"
    ;;
  pre:ios-swift|pre:android-kotlin)
    ;;  # no scaffolder; the template seeds the app skeleton

  post:ts-next)
    (cd "$p" && pnpm exec biome check --write . >/dev/null || true)
    ;;
  post:expo)
    # Generated native folders and Expo's cache aren't source; keep Biome out.
    node -e 'const f=process.argv[1]+"/biome.json",fs=require("fs"),j=JSON.parse(fs.readFileSync(f));
             j.files={...j.files,includes:["**","!**/ios","!**/android","!**/.expo","!**/assets"]};
             fs.writeFileSync(f,JSON.stringify(j,null,2)+"\n")' "$p"
    (cd "$p" && pnpm install --silent && pnpm exec biome check --write --unsafe . >/dev/null || true)
    ;;
  post:ios-swift)
    if [ "$(uname)" = Darwin ] && command -v xcodegen >/dev/null; then (cd "$p" && xcodegen generate --quiet); fi
    ;;
  post:android-kotlin)
    if command -v gradle >/dev/null; then (cd "$p" && gradle wrapper --quiet --gradle-version 8.14.3); fi
    ;;
  post:*) ;;
  *) echo "usage: scaffold.sh pre|post <layer> <dest> <path> [slug] [bundle_id]" >&2; exit 1 ;;
esac
