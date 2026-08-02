#!/usr/bin/env bash

set -euo pipefail

echo "==> Running core test runner"
swift run SwitchCommitCoreTestRunner

echo "==> Landing / Polar Node tests"
node --test Scripts/site-landing/lib/patch-index.test.mjs Scripts/polar-sync-dmg.test.mjs

echo "==> Building package"
swift build

echo "==> Settings navigation smoke (launches app UI)"
Scripts/smoke-settings-navigation.sh
