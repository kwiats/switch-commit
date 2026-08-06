#!/usr/bin/env bash
# End-to-end Linux install smoke test for the switch-commit CLI.
# Runs inside the Ubuntu image built from Dockerfile.cli-smoke, as the
# non-root "smoke" user, against a throwaway $HOME.
#
# Exercises: version, add, list, use, folder list, folder add, status, doctor,
# delete — and asserts the managed profiles.json and ~/.gitconfig include
# wiring were written.

set -euo pipefail

fail() {
  echo "SMOKE FAILURE: $*" >&2
  exit 1
}

profile_name="Docker User"
repo_dir="${HOME}/work/demo-repo"
profiles_json="${HOME}/.config/git-account-switcher/profiles.json"
gitconfig="${HOME}/.gitconfig"

echo "==> switch-commit version"
switch-commit version

echo "==> switch-commit add"
switch-commit add \
  --name "${profile_name}" \
  --git-name "Docker User" \
  --git-email "docker@example.com" \
  --access https

echo "==> switch-commit list"
switch-commit list

echo "==> switch-commit use"
switch-commit use "${profile_name}"

echo "==> switch-commit folder list"
switch-commit folder list

mkdir -p "${repo_dir}"
git init --quiet "${repo_dir}"

echo "==> switch-commit folder add"
switch-commit folder add "${repo_dir}" --profile "${profile_name}" --mode single-repo

echo "==> switch-commit status --path"
switch-commit status --path "${repo_dir}"

echo "==> switch-commit doctor --path"
switch-commit doctor --path "${repo_dir}"

echo "==> asserting managed profiles.json exists"
[[ -f "${profiles_json}" ]] || fail "expected profiles store at ${profiles_json}"
grep -q "${profile_name}" "${profiles_json}" || fail "profiles.json does not mention '${profile_name}'"

echo "==> asserting ~/.gitconfig wires the managed includes"
[[ -f "${gitconfig}" ]] || fail "expected ${gitconfig} to exist after add/folder add"
grep -q "git-account-switcher" "${gitconfig}" || fail "${gitconfig} does not reference git-account-switcher"

echo "==> switch-commit delete --yes"
switch-commit delete "${profile_name}" --yes

echo "Docker CLI smoke OK"
