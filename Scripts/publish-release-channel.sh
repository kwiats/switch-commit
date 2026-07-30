#!/usr/bin/env bash

set -euo pipefail

version="${1:?usage: Scripts/publish-release-channel.sh <version> <release-channel-dir> [repo-root]}"
release_channel_dir="${2:?usage: Scripts/publish-release-channel.sh <version> <release-channel-dir> [repo-root]}"
repo_root="${3:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
release_channel_base_url="https://kwiats.github.io/switch-commit-release-channel"
artifact_name="GitAccountSwitcher-v${version}-macOS.zip"
checksum_name="${artifact_name}.sha256"
release_dir="${repo_root}/dist/v${version}"
artifact_path="${release_dir}/${artifact_name}"
checksum_path="${release_dir}/${checksum_name}"
notes_source="${repo_root}/docs/release-notes/v${version}.md"
notes_destination="${release_channel_dir}/GitAccountSwitcher-v${version}-macOS.md"

if [[ ! "${version}" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
    echo "error: version must use X.Y.Z format without a leading v" >&2
    exit 1
fi

if [[ -z "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
    echo "error: SPARKLE_PRIVATE_ED_KEY must contain the private Sparkle EdDSA key" >&2
    exit 1
fi

if [[ ! -d "${release_channel_dir}/.git" ]]; then
    echo "error: release channel directory must be a checked-out git repository" >&2
    exit 1
fi

if [[ ! -f "${artifact_path}" ]]; then
    echo "error: missing release artifact ${artifact_path}" >&2
    exit 1
fi

if [[ ! -f "${checksum_path}" ]]; then
    echo "error: missing checksum ${checksum_path}" >&2
    exit 1
fi

generate_appcast_tool="$(
    find "${repo_root}/.build/artifacts" "${repo_root}/.build/checkouts" -name generate_appcast -type f 2>/dev/null | sort | head -n 1
)"

if [[ -z "${generate_appcast_tool}" ]]; then
    echo "error: Sparkle generate_appcast was not found under .build" >&2
    exit 1
fi

echo "==> Copying release artifacts into public release channel"
cp "${artifact_path}" "${release_channel_dir}/${artifact_name}"
cp "${checksum_path}" "${release_channel_dir}/${checksum_name}"

if [[ -f "${notes_source}" ]]; then
    cp "${notes_source}" "${notes_destination}"
else
    rm -f "${notes_destination}"
fi

echo "==> Generating Sparkle appcast"
printf '%s' "${SPARKLE_PRIVATE_ED_KEY}" | "${generate_appcast_tool}" \
    --ed-key-file - \
    --download-url-prefix "${release_channel_base_url}" \
    --release-notes-url-prefix "${release_channel_base_url}" \
    --versions "${version}" \
    "${release_channel_dir}"

echo "==> Public release channel contents updated"
