#!/usr/bin/env bash
set -euo pipefail
go version
command -v golangci-lint >/dev/null || {
  curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh | sh -s -- -b "$HOME/.local/bin"
  add_path "$HOME/.local/bin"
}
