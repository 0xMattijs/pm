#!/usr/bin/env bash
# GitHub's Ubuntu image ships a JDK and the Android SDK (ANDROID_HOME).
set -euo pipefail
java -version 2>&1 | head -1
echo "ANDROID_HOME=${ANDROID_HOME:-unset}"
