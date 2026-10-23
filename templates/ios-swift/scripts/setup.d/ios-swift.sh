#!/usr/bin/env bash
# Agent runs use Linux runners, where iOS checks skip; the macOS CI job on
# each PR builds and tests the app.
echo "ios-swift: no Linux toolchain; PR CI covers iOS on macOS"
