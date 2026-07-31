#!/usr/bin/env bash

set -euo pipefail

version="${1:?usage: Scripts/publish-release-channel.sh <version> [repo-root]}"
repo_root="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
github_repo="${GITHUB_REPOSITORY:-kwiats/switch-commit}"
github_download_prefix="https://github.com/${github_repo}/releases/download/v${version}"
artifact_name="SwitchCommit-v${version}-macOS.dmg"
checksum_name="${artifact_name}.sha256"
release_dir="${repo_root}/dist/v${version}"
artifact_path="${release_dir}/${artifact_name}"
checksum_path="${release_dir}/${checksum_name}"
notes_source="${repo_root}/docs/release-notes/v${version}.md"
notes_asset_path="${release_dir}/SwitchCommit-v${version}-macOS.md"
site_dir="${repo_root}/site"
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

if [[ ! -d "${site_dir}" ]]; then
    echo "error: missing site directory ${site_dir}" >&2
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

echo "==> Publishing GitHub Release ${tag} to ${github_repo}"
release_assets=("${artifact_path}" "${checksum_path}")
if [[ -f "${notes_source}" ]]; then
    mkdir -p "${release_dir}"
    cp "${notes_source}" "${notes_asset_path}"
    release_assets+=("${notes_asset_path}")
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
if [[ -f "${notes_asset_path}" ]]; then
    cp "${notes_asset_path}" "${appcast_staging}/SwitchCommit-v${version}-macOS.md"
fi

echo "==> Generating Sparkle appcast into site/"
generate_appcast_args=(
    --ed-key-file -
    --download-url-prefix "${github_download_prefix}/"
    --versions "${version}"
    -o "${site_dir}/appcast.xml"
    "${appcast_staging}"
)
if [[ -f "${notes_source}" ]]; then
    generate_appcast_args=(
        --ed-key-file -
        --download-url-prefix "${github_download_prefix}/"
        --release-notes-url-prefix "${github_download_prefix}/"
        --versions "${version}"
        -o "${site_dir}/appcast.xml"
        "${appcast_staging}"
    )
fi

printf '%s' "${normalized_private_key}" | "${generate_appcast_tool}" "${generate_appcast_args[@]}"

echo "==> Updating site/version.txt"
printf '%s\n' "${version}" > "${site_dir}/version.txt"

echo "==> Removing obsolete site artifact folders"
rm -rf "${site_dir}/release" "${site_dir}/releases"

trap - EXIT
cleanup_appcast_staging

echo "==> site/ channel metadata updated (landing owned by Scripts/site-landing/sync-landing.mjs)"
