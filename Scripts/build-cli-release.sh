#!/usr/bin/env bash
# Builds a release switch-commit CLI binary for the host OS/architecture and
# writes it to dist/v<version>/ using the stable asset name expected by
# CLIReleaseAsset.fileName (Sources/SwitchCommitCore/CLIReleaseAsset.swift):
#   linux   -> switch-commit-linux-<arch>
#   windows -> switch-commit-windows-<arch>.exe
#   macos   -> switch-commit-macos-<arch>
#
# Run this on the target OS (or inside a matching container) — it does not
# cross-compile. The macOS DMG flow (Scripts/build-release.sh) is unaffected;
# this script only produces the portable CLI asset for a given host.

set -euo pipefail

version="${1:?usage: Scripts/build-cli-release.sh <version>}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="${repo_root}/dist/v${version}"

if [[ ! "${version}" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
    echo "error: version must use X.Y.Z format without a leading v" >&2
    exit 1
fi

echo "==> Building release switch-commit binary"
cd "${repo_root}"
swift build -c release --product switch-commit

bin_path="$(swift build -c release --show-bin-path)/switch-commit"
if [[ ! -f "${bin_path}" && -f "${bin_path}.exe" ]]; then
    bin_path="${bin_path}.exe"
fi
if [[ ! -f "${bin_path}" ]]; then
    echo "error: built binary not found at ${bin_path}(.exe)" >&2
    exit 1
fi

host_os="$(uname -s 2>/dev/null || echo Windows)"
case "${host_os}" in
    Linux) asset_os="linux" ;;
    Darwin) asset_os="macos" ;;
    MINGW*|MSYS*|CYGWIN*|Windows*) asset_os="windows" ;;
    *)
        echo "error: unsupported host OS '${host_os}'" >&2
        exit 1
        ;;
esac

host_arch="$(uname -m 2>/dev/null || echo x86_64)"
case "${host_arch}" in
    x86_64|amd64|AMD64) asset_arch="x86_64" ;;
    arm64|aarch64) asset_arch="arm64" ;;
    *)
        echo "error: unsupported host architecture '${host_arch}'" >&2
        exit 1
        ;;
esac

if [[ "${asset_os}" == "windows" ]]; then
    asset_name="switch-commit-windows-${asset_arch}.exe"
else
    asset_name="switch-commit-${asset_os}-${asset_arch}"
fi

echo "==> Preparing ${release_dir}"
mkdir -p "${release_dir}"
asset_path="${release_dir}/${asset_name}"
checksum_path="${asset_path}.sha256"
version_path="${release_dir}/VERSION"

cp "${bin_path}" "${asset_path}"
chmod 755 "${asset_path}" 2>/dev/null || true

if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${asset_path}" | awk '{print $1}' > "${checksum_path}"
elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${asset_path}" | awk '{print $1}' > "${checksum_path}"
else
    echo "error: neither shasum nor sha256sum is available to compute a checksum" >&2
    exit 1
fi

# Sibling VERSION file so CLIVersion.current() can report a version on Linux/Windows,
# where there is no app bundle Info.plist to read from.
printf '%s\n' "${version}" > "${version_path}"

echo "==> CLI release artifacts"
printf '%s\n' "${asset_path}"
printf '%s\n' "${checksum_path}"
printf '%s\n' "${version_path}"
