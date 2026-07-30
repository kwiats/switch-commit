#!/usr/bin/env bash

set -euo pipefail

version="${1:?usage: Scripts/publish-release-channel.sh <version> <release-channel-dir> [repo-root]}"
release_channel_dir="${2:?usage: Scripts/publish-release-channel.sh <version> <release-channel-dir> [repo-root]}"
repo_root="${3:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
github_repo="kwiats/switch-commit-release-channel"
github_download_prefix="https://github.com/${github_repo}/releases/download/v${version}"
artifact_name="SwitchCommit-v${version}-macOS.dmg"
checksum_name="${artifact_name}.sha256"
release_dir="${repo_root}/dist/v${version}"
artifact_path="${release_dir}/${artifact_name}"
checksum_path="${release_dir}/${checksum_name}"
notes_source="${repo_root}/docs/release-notes/v${version}.md"
landing_template="${repo_root}/docs/release-channel/index.html"
tag="v${version}"

if [[ ! "${version}" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
    echo "error: version must use X.Y.Z format without a leading v" >&2
    exit 1
fi

if [[ -z "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
    echo "error: SPARKLE_PRIVATE_ED_KEY must contain the private Sparkle EdDSA key" >&2
    exit 1
fi

normalized_private_key="$(printf '%s' "${SPARKLE_PRIVATE_ED_KEY}" | tr -d '[:space:]')"

if [[ -z "${normalized_private_key}" ]] || ! printf '%s' "${normalized_private_key}" | base64 --decode >/dev/null 2>&1; then
    echo "error: SPARKLE_PRIVATE_ED_KEY must be the base64 contents exported by Sparkle generate_keys -x" >&2
    echo "error: do not use SUPublicEDKey, XML plist snippets, a file path, or shell assignment text" >&2
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

if [[ ! -f "${landing_template}" ]]; then
    echo "error: missing landing template ${landing_template}" >&2
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh is required to publish GitHub Releases" >&2
    exit 1
fi

generate_appcast_tool="$(
    find "${repo_root}/.build/artifacts" "${repo_root}/.build/checkouts" -name generate_appcast -type f 2>/dev/null | sort | head -n 1
)"

if [[ -z "${generate_appcast_tool}" ]]; then
    echo "error: Sparkle generate_appcast was not found under .build" >&2
    exit 1
fi

echo "==> Publishing GitHub Release ${tag}"
release_assets=("${artifact_path}" "${checksum_path}")
if [[ -f "${notes_source}" ]]; then
    if gh release view "${tag}" --repo "${github_repo}" >/dev/null 2>&1; then
        gh release upload "${tag}" "${release_assets[@]}" --repo "${github_repo}" --clobber
        gh release edit "${tag}" --repo "${github_repo}" --notes-file "${notes_source}"
    else
        gh release create "${tag}" "${release_assets[@]}" \
            --repo "${github_repo}" \
            --title "Switch Commit ${version}" \
            --notes-file "${notes_source}"
    fi
else
    if gh release view "${tag}" --repo "${github_repo}" >/dev/null 2>&1; then
        gh release upload "${tag}" "${release_assets[@]}" --repo "${github_repo}" --clobber
    else
        gh release create "${tag}" "${release_assets[@]}" \
            --repo "${github_repo}" \
            --title "Switch Commit ${version}" \
            --notes "Switch Commit ${version}"
    fi
fi

appcast_staging="$(mktemp -d "${TMPDIR:-/tmp}/switch-commit-appcast.XXXXXX")"
cleanup_appcast_staging() {
    rm -rf "${appcast_staging}"
}
trap cleanup_appcast_staging EXIT

cp "${artifact_path}" "${appcast_staging}/${artifact_name}"
if [[ -f "${notes_source}" ]]; then
    cp "${notes_source}" "${appcast_staging}/SwitchCommit-v${version}-macOS.md"
fi

echo "==> Generating Sparkle appcast"
generate_appcast_args=(
    --ed-key-file -
    --download-url-prefix "${github_download_prefix}/"
    --versions "${version}"
    -o "${release_channel_dir}/appcast.xml"
    "${appcast_staging}"
)
if [[ -f "${notes_source}" ]]; then
    generate_appcast_args=(
        --ed-key-file -
        --download-url-prefix "${github_download_prefix}/"
        --release-notes-url-prefix "${github_download_prefix}/"
        --versions "${version}"
        -o "${release_channel_dir}/appcast.xml"
        "${appcast_staging}"
    )
fi

printf '%s' "${normalized_private_key}" | "${generate_appcast_tool}" "${generate_appcast_args[@]}"

echo "==> Updating Pages landing metadata"
printf '%s\n' "${version}" > "${release_channel_dir}/version.txt"

dmg_url="${github_download_prefix}/${artifact_name}"
sha256_url="${github_download_prefix}/${checksum_name}"
python3 - "${landing_template}" "${release_channel_dir}/index.html" "${version}" "${dmg_url}" "${sha256_url}" <<'PY'
import pathlib
import sys

template_path, output_path, version, dmg_url, sha256_url = sys.argv[1:6]
rendered = (
    pathlib.Path(template_path)
    .read_text(encoding="utf-8")
    .replace("__VERSION__", version)
    .replace("__VERSION_TAG__", f"v{version}")
    .replace("__DMG_URL__", dmg_url)
    .replace("__SHA256_URL__", sha256_url)
)
pathlib.Path(output_path).write_text(rendered, encoding="utf-8")
PY

echo "==> Removing obsolete Pages artifact folders"
rm -rf "${release_channel_dir}/release" "${release_channel_dir}/releases"

trap - EXIT
cleanup_appcast_staging

echo "==> Public release channel contents updated"
