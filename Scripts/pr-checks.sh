#!/usr/bin/env bash

set -euo pipefail

echo "==> Running core test runner"
swift run SwitchCommitCoreTestRunner

echo "==> Building package"
swift build
