#!/usr/bin/env bash
set -euo pipefail
if ! command -v flutter >/dev/null; then
  git clone --quiet --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
  add_path "$HOME/flutter/bin"
fi
flutter --version
