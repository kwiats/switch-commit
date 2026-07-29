#!/usr/bin/env bash

set -euo pipefail

echo "==> Running core test runner"
swift run GitAccountSwitcherCoreTestRunner

echo "==> Building package"
swift build

