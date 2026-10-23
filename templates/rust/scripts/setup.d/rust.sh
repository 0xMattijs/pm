#!/usr/bin/env bash
set -euo pipefail
command -v rustup >/dev/null || { curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal; add_path "$HOME/.cargo/bin"; }
rustup component add rustfmt clippy
cargo --version
