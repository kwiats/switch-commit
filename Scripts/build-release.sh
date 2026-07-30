#!/usr/bin/env bash

set -euo pipefail

version="${1:-0.1.1}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_root="${repo_root}/dist"
release_dir="${dist_root}/v${version}"
app_name="Switch Commit"
app_bundle="${release_dir}/${app_name}.app"
binary_name="SwitchCommitApp"
bundle_id="com.git-account-switcher.app"
release_channel_base_url="https://kwiats.github.io/switch-commit-release-channel"
sparkle_feed_url="${release_channel_base_url}/appcast.xml"
sparkle_artifact_url="https://github.com/kwiats/switch-commit-release-channel/releases/download/v${version}/SwitchCommit-v${version}-macOS.dmg"
sparkle_public_ed_key="x4XXCgBb5YuShR9DnY81L9bPJ+6vFaKeL46WK/fEte8="
frameworks_dir="${app_bundle}/Contents/Frameworks"

echo "==> Building release binary"
cd "${repo_root}"
swift build -c release --product "${binary_name}"

echo "==> Preparing app bundle"
rm -rf "${release_dir}"
mkdir -p "${app_bundle}/Contents/MacOS"
mkdir -p "${app_bundle}/Contents/Resources"
mkdir -p "${frameworks_dir}"

cp "${repo_root}/.build/release/${binary_name}" "${app_bundle}/Contents/MacOS/${binary_name}"
chmod 755 "${app_bundle}/Contents/MacOS/${binary_name}"

sparkle_framework_source="$(
    find "${repo_root}/.build/artifacts" "${repo_root}/.build/release" -name Sparkle.framework -type d 2>/dev/null | sort | head -n 1
)"
sparkle_framework_destination="${frameworks_dir}/Sparkle.framework"

if [[ -z "${sparkle_framework_source}" ]]; then
    echo "error: Sparkle.framework was not found in .build artifacts" >&2
    exit 1
fi

ditto "${sparkle_framework_source}" "${sparkle_framework_destination}"

if ! otool -l "${app_bundle}/Contents/MacOS/${binary_name}" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${app_bundle}/Contents/MacOS/${binary_name}"
fi

cat > "${app_bundle}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${app_name}</string>
    <key>CFBundleExecutable</key>
    <string>${binary_name}</string>
    <key>CFBundleIdentifier</key>
    <string>${bundle_id}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${app_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
    <key>CFBundleVersion</key>
    <string>${version}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2026 Switch Commit contributors</string>
    <key>SUEnableAutomaticChecks</key>
    <false/>
    <key>SUFeedURL</key>
    <string>${sparkle_feed_url}</string>
    <key>SUPublicEDKey</key>
    <string>${sparkle_public_ed_key}</string>
</dict>
</plist>
PLIST

echo "==> Signing app bundle"
codesign --force --deep --sign - "${sparkle_framework_destination}"
codesign --force --deep --sign - "${app_bundle}"

echo "==> Creating DMG artifact"
dmg_name="SwitchCommit-v${version}-macOS.dmg"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/switch-commit-dmg.XXXXXX")"
cleanup_staging() {
    rm -rf "${staging_dir}"
}
trap cleanup_staging EXIT

ditto "${app_bundle}" "${staging_dir}/${app_name}.app"
ln -s /Applications "${staging_dir}/Applications"

rm -f "${release_dir}/${dmg_name}"
hdiutil create \
    -volname "${app_name}" \
    -srcfolder "${staging_dir}" \
    -ov \
    -format UDZO \
    "${release_dir}/${dmg_name}"

shasum -a 256 "${release_dir}/${dmg_name}" > "${release_dir}/${dmg_name}.sha256"
printf '%s\n' "${sparkle_artifact_url}" > "${release_dir}/release-url.txt"

trap - EXIT
cleanup_staging

echo "==> Release artifacts"
printf '%s\n' "${release_dir}/${dmg_name}"
printf '%s\n' "${release_dir}/${dmg_name}.sha256"
printf '%s\n' "${release_dir}/release-url.txt"
