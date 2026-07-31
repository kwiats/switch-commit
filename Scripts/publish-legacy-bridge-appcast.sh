#!/usr/bin/env bash

set -euo pipefail

# After publishing vX.Y.Z to kwiats/switch-commit, prepend that Sparkle <item>
# into the legacy channel appcast so 0.2.x clients can bridge to the new feed.
#
# Usage: Scripts/publish-legacy-bridge-appcast.sh <version> [legacy-repo]

version="${1:?usage: Scripts/publish-legacy-bridge-appcast.sh <version> [legacy-repo]}"
legacy_repo="${2:-kwiats/switch-commit-release-channel}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
new_appcast="${repo_root}/site/appcast.xml"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/switch-commit-bridge.XXXXXX")"
cleanup() { rm -rf "${workdir}"; }
trap cleanup EXIT

if [[ ! "${version}" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
    echo "error: version must use X.Y.Z format without a leading v" >&2
    exit 1
fi

if [[ ! -f "${new_appcast}" ]]; then
    echo "error: missing ${new_appcast}; publish the new-channel release first" >&2
    exit 1
fi

item="$(
    python3 - "${new_appcast}" "${version}" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
version = sys.argv[2]
match = re.search(
    rf"<item>\s*<title>{re.escape(version)}</title>.*?</item>",
    text,
    flags=re.S,
)
if not match:
    raise SystemExit(f"error: site/appcast.xml has no <item> for {version}")
print(match.group(0))
PY
)"

echo "==> Cloning ${legacy_repo}"
git clone --depth 1 "https://github.com/${legacy_repo}.git" "${workdir}/legacy"

python3 - "${workdir}/legacy/appcast.xml" "${item}" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
item = sys.argv[2].strip() + "\n"
text = path.read_text(encoding="utf-8")
# Drop an existing item for the same title if present.
title = re.search(r"<title>([^<]+)</title>", item).group(1)
text = re.sub(
    rf"\s*<item>\s*<title>{re.escape(title)}</title>.*?</item>",
    "",
    text,
    count=1,
    flags=re.S,
)
text = text.replace("<channel>", "<channel>\n        " + item, 1)
path.write_text(text, encoding="utf-8")
print(f"bridged item {title} into legacy appcast")
PY

git -C "${workdir}/legacy" config user.name "github-actions[bot]"
git -C "${workdir}/legacy" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "${workdir}/legacy" add appcast.xml
if git -C "${workdir}/legacy" diff --cached --quiet; then
    echo "No legacy appcast changes."
    exit 0
fi
git -C "${workdir}/legacy" commit -m "Bridge Sparkle clients to Switch Commit v${version}"
git -C "${workdir}/legacy" push origin HEAD:main
echo "==> Legacy bridge appcast published"
