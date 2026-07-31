#!/usr/bin/env bash

set -euo pipefail

# Copy historical GitHub Releases from the legacy channel into this repository.
# Usage: Scripts/migrate-legacy-releases.sh [source-repo] [dest-repo]

source_repo="${1:-kwiats/switch-commit-release-channel}"
dest_repo="${2:-kwiats/switch-commit}"
tags=("v0.2.5" "v0.2.6")
workdir="$(mktemp -d "${TMPDIR:-/tmp}/switch-commit-migrate.XXXXXX")"
cleanup() { rm -rf "${workdir}"; }
trap cleanup EXIT

if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh is required" >&2
    exit 1
fi

for tag in "${tags[@]}"; do
    echo "==> Migrating ${tag}"
    tag_dir="${workdir}/${tag}"
    mkdir -p "${tag_dir}"
    assets_json="$(gh api "repos/${source_repo}/releases/tags/${tag}")"
    notes="$(printf '%s' "${assets_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("body") or "")')"
    title="$(printf '%s' "${assets_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name") or sys.argv[1])' "${tag}")"
    printf '%s' "${assets_json}" | python3 -c '
import json,sys
release=json.load(sys.stdin)
for asset in release.get("assets") or []:
    print(asset["name"] + "\t" + asset["browser_download_url"])
' > "${tag_dir}/assets.tsv"

    asset_paths=()
    while IFS=$'\t' read -r name url; do
        [[ -z "${name}" ]] && continue
        out="${tag_dir}/${name}"
        echo "    downloading ${name}"
        curl -fsSL -o "${out}" "${url}"
        asset_paths+=("${out}")
    done < "${tag_dir}/assets.tsv"

    notes_file="${tag_dir}/notes.md"
    printf '%s\n' "${notes}" > "${notes_file}"

    if gh release view "${tag}" --repo "${dest_repo}" >/dev/null 2>&1; then
        echo "    destination release exists; uploading assets with --clobber"
        if ((${#asset_paths[@]} > 0)); then
            gh release upload "${tag}" "${asset_paths[@]}" --repo "${dest_repo}" --clobber
        fi
        gh release edit "${tag}" --repo "${dest_repo}" --title "${title}" --notes-file "${notes_file}"
    else
        echo "    creating destination release"
        if ((${#asset_paths[@]} > 0)); then
            gh release create "${tag}" "${asset_paths[@]}" \
                --repo "${dest_repo}" \
                --title "${title}" \
                --notes-file "${notes_file}" \
                --target "$(gh api "repos/${dest_repo}" --jq .default_branch)"
        else
            gh release create "${tag}" \
                --repo "${dest_repo}" \
                --title "${title}" \
                --notes-file "${notes_file}" \
                --target "$(gh api "repos/${dest_repo}" --jq .default_branch)"
        fi
    fi
done

echo "==> Legacy releases migrated to ${dest_repo}"
