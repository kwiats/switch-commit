# DMG Release Artifact And Switch Commit Rename Design

## Goal

Ship one release that:

1. replaces the ZIP distribution artifact with a compressed installer DMG,
2. renames the customer-facing and Swift package surface from Git Account Switcher to Switch Commit,
3. preserves technical identity so existing installs can Sparkle-update and keep profiles.

## Decisions

- Publish only DMG (no ZIP).
- Installer layout: `Switch Commit.app` + symlink to `/Applications`.
- Build the DMG with native `hdiutil` UDZO (no `create-dmg`).
- Keep ad-hoc signing and the existing public release-channel / Sparkle EdDSA flow.
- Rename user-visible names and SPM targets/modules/binaries to Switch Commit.
- Keep continuity identifiers unchanged (see below).

## Continuity Identifiers (Unchanged)

These must stay so current users update cleanly and retain data:

- `CFBundleIdentifier`: `com.git-account-switcher.app`
- managed Git config root: `~/.config/git-account-switcher/`
- managed SSH include: `~/.ssh/git-account-switcher.conf`
- Keychain reference prefix: `git-account-switcher.<profile-id>.<purpose>`

Private source repository remotes and historical docs may keep older names where rewriting history is unnecessary. Runtime product chrome and new release assets must say Switch Commit.

## Artifact Contract

For version `X.Y.Z`, release outputs under `dist/vX.Y.Z/` become:

```text
Switch Commit.app
SwitchCommit-vX.Y.Z-macOS.dmg
SwitchCommit-vX.Y.Z-macOS.dmg.sha256
release-url.txt
```

Public artifact URL:

```text
https://kwiats.github.io/switch-commit-release-channel/release/SwitchCommit-vX.Y.Z-macOS.dmg
```

`release-url.txt` must contain that URL.

## Product And Package Rename

Rename the shipping surface:

- app bundle / display name: `Switch Commit`
- executable / SPM products: `SwitchCommitApp` (and matching Core / AppLogic / TestRunner product names)
- source directories under `Sources/`: `SwitchCommitCore`, `SwitchCommitAppLogic`, `SwitchCommitApp`, `SwitchCommitCoreTestRunner`
- module imports and test-runner references updated to match
- release scripts, README, AGENTS/CLAUDE guidance, and active release docs use Switch Commit naming for the app and artifacts

Do not rename continuity paths or Keychain prefixes listed above.

## Build Pipeline

`Scripts/build-release.sh` continues to:

1. build the release binary for the renamed app product,
2. assemble and ad-hoc sign `Switch Commit.app` (including bundled `Sparkle.framework`),
3. embed `SUFeedURL` and `SUPublicEDKey` as today,
4. keep `CFBundleIdentifier` as `com.git-account-switcher.app`.

After the app exists, instead of ZIP creation it must:

1. create a temporary staging directory,
2. copy the `.app` into staging preserving the bundle,
3. add a symlink named `Applications` pointing at `/Applications`,
4. create a compressed UDZO DMG named `SwitchCommit-v${version}-macOS.dmg`,
5. write the SHA-256 checksum beside the DMG,
6. write the `.dmg` public URL into `release-url.txt`,
7. remove the staging directory.

DMG volume / file naming must stay deterministic and versioned.

## Publish Pipeline

`Scripts/publish-release-channel.sh` must expect and copy:

- `SwitchCommit-v${version}-macOS.dmg`
- `SwitchCommit-v${version}-macOS.dmg.sha256`
- optional `docs/release-notes/v${version}.md`

Sparkle `generate_appcast` invocation stays the same and will publish enclosure URLs for the DMG.

Release-channel commit messages should say `Switch Commit vX.Y.Z`.

## Documentation And Tests

Update:

- README install/release instructions for DMG drag-to-Applications and Switch Commit naming,
- verification commands to the renamed test-runner product,
- contract tests that currently assert Git Account Switcher / ZIP paths,
- AGENTS.md / CLAUDE.md package layout names where they describe current sources.

Historical release notes for older versions may keep original artifact filenames from those releases.

## Out Of Scope

- Branded DMG window backgrounds, icon positioning, or custom Finder layout polish.
- Developer ID signing and notarization.
- Changing bundle id, managed config paths, or Keychain prefixes.
- Migrating or rewriting historical appcast entries that still point at older ZIP files.
- Publishing both ZIP and DMG.

## Success Criteria

- Tag release builds produce `SwitchCommit-vX.Y.Z-macOS.dmg` + `.sha256` and no release ZIP.
- The DMG contains `Switch Commit.app` and an Applications shortcut.
- Public channel `release/` hosts the DMG; `appcast.xml` enclosure URL ends with `.dmg`.
- Existing installs with the old display name can Sparkle-update because the bundle id is unchanged.
- Profiles and Keychain references continue to resolve through unchanged managed paths/prefixes.
- Verification passes with the renamed runner: `swift run SwitchCommitCoreTestRunner` and `swift build`.
