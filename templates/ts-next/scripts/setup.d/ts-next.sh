#!/usr/bin/env bash
# Node from the runner image; pnpm through corepack at the version package.json pins.
set -euo pipefail
node --version
corepack enable pnpm 2>/dev/null || sudo corepack enable pnpm
pnpm --version
