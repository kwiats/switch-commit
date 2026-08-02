#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

echo "==> Building SwitchCommitApp for Settings navigation smoke"
swift build --product SwitchCommitApp

app_binary="${repo_root}/.build/debug/SwitchCommitApp"
if [[ ! -x "${app_binary}" ]]; then
  echo "error: missing ${app_binary}" >&2
  exit 1
fi

echo "==> Running Settings navigation smoke (includes Updates blank regression)"
"${app_binary}" --smoke-settings-navigation
