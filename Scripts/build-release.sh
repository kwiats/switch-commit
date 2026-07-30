#!/usr/bin/env bash

set -euo pipefail

version="${1:-0.1.1}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_root="${repo_root}/dist"
release_dir="${dist_root}/v${version}"
app_name="Git Account Switcher"
app_bundle="${release_dir}/${app_name}.app"
binary_name="GitAccountSwitcherApp"
bundle_id="com.git-account-switcher.app"

echo "==> Building release binary"
cd "${repo_root}"
swift build -c release --product "${binary_name}"

echo "==> Preparing app bundle"
rm -rf "${release_dir}"
mkdir -p "${app_bundle}/Contents/MacOS"
mkdir -p "${app_bundle}/Contents/Resources"

cp "${repo_root}/.build/release/${binary_name}" "${app_bundle}/Contents/MacOS/${binary_name}"
chmod 755 "${app_bundle}/Contents/MacOS/${binary_name}"

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
    <string>Copyright 2026 Git Account Switcher contributors</string>
</dict>
</plist>
PLIST

echo "==> Creating ZIP artifact"
(
    cd "${release_dir}"
    ditto -c -k --norsrc --keepParent "${app_name}.app" "GitAccountSwitcher-v${version}-macOS.zip"
    shasum -a 256 "GitAccountSwitcher-v${version}-macOS.zip" > "GitAccountSwitcher-v${version}-macOS.zip.sha256"
)

echo "==> Release artifacts"
printf '%s\n' "${release_dir}/GitAccountSwitcher-v${version}-macOS.zip"
printf '%s\n' "${release_dir}/GitAccountSwitcher-v${version}-macOS.zip.sha256"
