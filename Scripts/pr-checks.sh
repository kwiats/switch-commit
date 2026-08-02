#!/usr/bin/env bash

set -euo pipefail

echo "==> Running core test runner"
swift run SwitchCommitCoreTestRunner

echo "==> Building package"
swift build

echo "==> Settings navigation smoke (launches app UI)"
Scripts/smoke-settings-navigation.sh
