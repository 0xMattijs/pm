#!/usr/bin/env bash
# uv manages Python itself; the project's .python-version is honored.
set -euo pipefail
command -v uv >/dev/null || { curl -LsSf https://astral.sh/uv/install.sh | sh; add_path "$HOME/.local/bin"; }
uv --version
