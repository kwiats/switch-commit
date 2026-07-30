# DMG Release And Switch Commit Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ZIP release artifact with an installer DMG and rename the shipping Swift package/app surface to Switch Commit while preserving Sparkle and Keychain continuity identifiers.

**Architecture:** Keep continuity IDs (`CFBundleIdentifier`, managed paths, Keychain account prefix, `kSecAttrService`) unchanged. Rename SPM package/targets/modules/binaries and user-facing app/artifact names to Switch Commit. Change `Scripts/build-release.sh` to emit a UDZO DMG with `Switch Commit.app` plus an Applications symlink; update publish scripts, contract tests, and docs to match.

**Tech Stack:** Swift 6.2 package, Bash (`hdiutil`, `ditto`), GitHub Actions, Sparkle `generate_appcast`, local `SwitchCommitCoreTestRunner`.

**Worktree:** Implement from `/Users/pawelkwiatkowski/Documents/New project/.worktrees/dmg-release-artifact` on branch `codex/dmg-release-artifact`.

---

## File Structure

| Path | Responsibility after change |
| --- | --- |
| `Package.swift` | Package/products/targets named `SwitchCommit*` |
| `Sources/SwitchCommitCore/` | Renamed core module; keep path/Keychain continuity strings |
| `Sources/SwitchCommitAppLogic/` | Renamed app-logic module |
| `Sources/SwitchCommitApp/` | Renamed app target; `SwitchCommitApp.swift` entrypoint |
| `Sources/SwitchCommitCoreTestRunner/` | Renamed test runner executable |
| `Scripts/build-release.sh` | Build `Switch Commit.app`, create `.dmg`, write checksum/URL |
| `Scripts/publish-release-channel.sh` | Copy `.dmg` assets and regenerate appcast |
| `Scripts/pr-checks.sh` | Run renamed test runner |
| `.github/workflows/release.yml` | Commit message uses Switch Commit; still calls scripts |
| `README.md`, `AGENTS.md`, `CLAUDE.md` | Document Switch Commit + DMG + new commands |
| `docs/superpowers/specs/2026-07-30-dmg-release-artifact-design.md` | Approved design (already present) |

### Continuity hard constraints

Do **not** change:

- `com.git-account-switcher.app`
- `~/.config/git-account-switcher/`
- `~/.ssh/git-account-switcher.conf`
- `git-account-switcher.<profile-id>.<purpose>`
- Keychain `kSecAttrService` value `GitAccountSwitcher`

---

### Task 1: Fail contract tests for DMG + Switch Commit artifact names

**Files:**
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift` (still old path until Task 2)
- Test: same file, release-script contract tests around the Sparkle/ZIP assertions

- [ ] **Step 1: Update release contract expectations to the new names**

In the tests named like `release build script embeds Switch Commit Sparkle channel configuration`, `release build script keeps appcast and artifact URLs on the public release channel`, and `release channel publisher signs appcast...`, change assertions from ZIP / Git Account Switcher to:

```swift
try expect(source.contains("app_name=\"Switch Commit\""), "release script should ship Switch Commit.app")
try expect(source.contains("binary_name=\"SwitchCommitApp\""), "release script should build SwitchCommitApp")
try expect(
    source.contains("sparkle_artifact_url=\"${release_channel_base_url}/release/SwitchCommit-v${version}-macOS.dmg\""),
    "release script should derive DMG artifact URL from the public channel release folder"
)
try expect(source.contains("hdiutil create"), "release script should create a DMG with hdiutil")
try expect(source.contains("Applications"), "release script should include an Applications symlink in the DMG")
try expect(!source.contains("macOS.zip"), "release script should not publish a ZIP artifact")
```

And in the publisher test:

```swift
try expect(source.contains("SwitchCommit-v${version}-macOS.dmg"), "publisher should copy the release DMG")
try expect(!source.contains("macOS.zip"), "publisher should not copy a ZIP artifact")
```

Also update the README contract test expectations from `.zip` to `.dmg` and from `GitAccountSwitcherCoreTestRunner` to `SwitchCommitCoreTestRunner` where those strings are asserted.

- [ ] **Step 2: Run tests to verify they fail against current scripts**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: FAIL on the updated release/README contract assertions.

- [ ] **Step 3: Commit the failing expectations**

```bash
git add Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "$(cat <<'EOF'
test: expect Switch Commit DMG release artifacts

EOF
)"
```

---

### Task 2: Rename SPM package, targets, and source directories

**Files:**
- Modify: `Package.swift`
- Rename dirs: `Sources/GitAccountSwitcherCore` -> `Sources/SwitchCommitCore` (and AppLogic/App/TestRunner equivalents)
- Rename: `Sources/.../GitAccountSwitcherApp.swift` -> `SwitchCommitApp.swift`
- Modify imports/types across Swift sources and test runner

- [ ] **Step 1: Rewrite Package.swift products/targets**

Replace package contents with:

```swift
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwitchCommit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SwitchCommitCore", targets: ["SwitchCommitCore"]),
        .library(name: "SwitchCommitAppLogic", targets: ["SwitchCommitAppLogic"]),
        .executable(name: "SwitchCommitApp", targets: ["SwitchCommitApp"]),
        .executable(name: "SwitchCommitCoreTestRunner", targets: ["SwitchCommitCoreTestRunner"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .target(name: "SwitchCommitCore"),
        .target(
            name: "SwitchCommitAppLogic",
            dependencies: ["SwitchCommitCore"]
        ),
        .executableTarget(
            name: "SwitchCommitApp",
            dependencies: [
                "SwitchCommitAppLogic",
                "SwitchCommitCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "SwitchCommitCoreTestRunner",
            dependencies: [
                "SwitchCommitAppLogic",
                "SwitchCommitCore"
            ]
        )
    ]
)
```

- [ ] **Step 2: Move source directories and app entry file**

```bash
git mv Sources/GitAccountSwitcherCore Sources/SwitchCommitCore
git mv Sources/GitAccountSwitcherAppLogic Sources/SwitchCommitAppLogic
git mv Sources/GitAccountSwitcherApp Sources/SwitchCommitApp
git mv Sources/GitAccountSwitcherCoreTestRunner Sources/SwitchCommitCoreTestRunner
git mv Sources/SwitchCommitApp/GitAccountSwitcherApp.swift Sources/SwitchCommitApp/SwitchCommitApp.swift
```

- [ ] **Step 3: Bulk-rename modules and public types in Swift**

Apply these renames everywhere under `Sources/` (including tests):

| Old | New |
| --- | --- |
| `import GitAccountSwitcherCore` | `import SwitchCommitCore` |
| `import GitAccountSwitcherAppLogic` | `import SwitchCommitAppLogic` |
| `GitAccountSwitcherError` | `SwitchCommitError` |
| `GitAccountSwitcherApp` | `SwitchCommitApp` |

Keep unchanged:

```swift
kSecAttrService as String: "GitAccountSwitcher"
```

and all `git-account-switcher` path/account strings.

In `SwitchCommitApp.swift`, keep user-facing chrome already using `"Switch Commit"` and update debug `print("SwitchCommitApp ...")` strings to the new binary name.

- [ ] **Step 4: Update pr-checks and agent docs commands**

`Scripts/pr-checks.sh`:

```bash
swift run SwitchCommitCoreTestRunner
```

`AGENTS.md` / `CLAUDE.md`: replace layout names and commands with `SwitchCommit*` / `swift run SwitchCommitCoreTestRunner`.

- [ ] **Step 5: Build and run renamed runner**

```bash
swift run SwitchCommitCoreTestRunner
swift build
```

Expected: package builds; release-script contract tests still FAIL until Task 3; other tests PASS.

- [ ] **Step 6: Commit rename**

```bash
git add -A Package.swift Sources Scripts/pr-checks.sh AGENTS.md CLAUDE.md
git commit -m "$(cat <<'EOF'
refactor: rename package surface to Switch Commit

EOF
)"
```

---

### Task 3: Build installer DMG instead of ZIP

**Files:**
- Modify: `Scripts/build-release.sh`
- Modify: `Scripts/publish-release-channel.sh`
- Modify: `.github/workflows/release.yml` (commit message only if needed)
- Modify: `README.md`

- [ ] **Step 1: Update build-release.sh naming and DMG creation**

Set:

```bash
app_name="Switch Commit"
binary_name="SwitchCommitApp"
bundle_id="com.git-account-switcher.app"
sparkle_artifact_url="${release_channel_base_url}/release/SwitchCommit-v${version}-macOS.dmg"
```

Replace the ZIP block with:

```bash
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
```

Keep Info.plist `CFBundleDisplayName` / `CFBundleName` as `${app_name}` (`Switch Commit`) and `CFBundleIdentifier` as `${bundle_id}`.

- [ ] **Step 2: Update publish-release-channel.sh**

```bash
artifact_name="SwitchCommit-v${version}-macOS.dmg"
checksum_name="${artifact_name}.sha256"
notes_destination="${release_channel_assets_dir}/SwitchCommit-v${version}-macOS.md"
```

Remove any remaining `macOS.zip` references.

- [ ] **Step 3: Update workflow commit message**

In `.github/workflows/release.yml`:

```bash
git commit -m "Release Switch Commit v${{ steps.version.outputs.version }}"
```

(If already Switch Commit, leave as-is.)

- [ ] **Step 4: Update README release section**

Title/header and install instructions should say Switch Commit. Release build section:

```bash
Scripts/build-release.sh 0.2.5
```

Artifacts:

```text
SwitchCommit-v0.2.5-macOS.dmg
SwitchCommit-v0.2.5-macOS.dmg.sha256
release-url.txt
```

Install: open the DMG and drag `Switch Commit.app` to Applications.

Example appcast URL ends with `SwitchCommit-v0.2.5-macOS.dmg`.

Development commands use `swift run SwitchCommitCoreTestRunner`.

- [ ] **Step 5: Run verification**

```bash
swift run SwitchCommitCoreTestRunner
swift build
```

Expected: all tests PASS.

Optional local smoke (skip in CI-less environments if hdiutil prompts):

```bash
Scripts/build-release.sh 0.2.5
ls dist/v0.2.5/SwitchCommit-v0.2.5-macOS.dmg
hdiutil attach dist/v0.2.5/SwitchCommit-v0.2.5-macOS.dmg -readonly -nobrowse
# confirm Switch Commit.app + Applications symlink, then detach
```

- [ ] **Step 6: Commit**

```bash
git add Scripts/build-release.sh Scripts/publish-release-channel.sh .github/workflows/release.yml README.md
git commit -m "$(cat <<'EOF'
feat: ship Switch Commit releases as installer DMG

EOF
)"
```

---

### Task 4: Final docs pass and branch readiness

**Files:**
- Modify only if still stale: `docs/release-notes/` for the upcoming version (create notes for the release that introduces DMG+rename if tagging soon)
- Do not rewrite historical `v0.1.x` artifact filenames

- [ ] **Step 1: Grep for leftover shipping names**

```bash
rg -n 'Git Account Switcher|GitAccountSwitcher|macOS\.zip' README.md AGENTS.md CLAUDE.md Scripts Sources Package.swift .github || true
```

Expected leftovers only inside continuity strings (`kSecAttrService`, paths, bundle id) or intentional historical docs.

- [ ] **Step 2: Re-run verification**

```bash
Scripts/pr-checks.sh
```

Expected: all tests passed + build complete.

- [ ] **Step 3: Commit any remaining doc fixes**

```bash
git add README.md AGENTS.md CLAUDE.md docs/release-notes || true
git commit -m "$(cat <<'EOF'
docs: align Switch Commit DMG release instructions

EOF
)" || true
```

---

## Spec Coverage Check

| Spec requirement | Task |
| --- | --- |
| DMG only, no ZIP | Task 3 |
| App + Applications symlink via hdiutil | Task 3 |
| Artifact `SwitchCommit-vX.Y.Z-macOS.dmg` | Tasks 1 + 3 |
| Rename SPM/app surface to Switch Commit | Task 2 |
| Keep bundle id / paths / Keychain service+prefix | Tasks 2–3 constraints |
| Update publish + appcast flow | Task 3 |
| Update README/tests/commands | Tasks 1–4 |

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-30-dmg-release-and-switch-commit-rename.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks
2. **Inline Execution** — execute tasks in this session with checkpoints

Which approach?
