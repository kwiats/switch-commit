# DMG Release Artifact Design

## Goal

Replace the Switch Commit release ZIP artifact with a compressed `.dmg` that contains the signed `.app` bundle and an `Applications` symlink. Manual install and Sparkle updates use the same public artifact.

## Decision

- Publish only DMG (no ZIP).
- Use a simple installer layout: app + symlink to `/Applications`.
- Build the DMG with native `hdiutil` (no `create-dmg` or other external packaging tools).
- Keep ad-hoc signing and the existing public release-channel / Sparkle EdDSA flow unchanged.

## Artifact Contract

For version `X.Y.Z`, release outputs under `dist/vX.Y.Z/` become:

```text
Git Account Switcher.app
GitAccountSwitcher-vX.Y.Z-macOS.dmg
GitAccountSwitcher-vX.Y.Z-macOS.dmg.sha256
release-url.txt
```

Public artifact URL:

```text
https://kwiats.github.io/switch-commit-release-channel/release/GitAccountSwitcher-vX.Y.Z-macOS.dmg
```

`release-url.txt` must contain that URL.

## Build Pipeline

`Scripts/build-release.sh` continues to:

1. build the release binary,
2. assemble and ad-hoc sign the `.app` (including bundled `Sparkle.framework`),
3. embed `SUFeedURL` and `SUPublicEDKey` as today.

After the app exists, instead of `ditto` ZIP creation it must:

1. create a temporary staging directory,
2. copy the `.app` into staging with `ditto` / `cp -R` preserving the bundle,
3. add a symlink named `Applications` pointing at `/Applications`,
4. create a compressed UDZO DMG with `hdiutil create` from that staging directory,
5. write the SHA-256 checksum beside the DMG,
6. write the `.dmg` public URL into `release-url.txt`,
7. remove the staging directory.

DMG volume / file naming should stay deterministic and versioned so CI diffs and appcast generation remain stable.

## Publish Pipeline

`Scripts/publish-release-channel.sh` must expect and copy:

- `GitAccountSwitcher-v${version}-macOS.dmg`
- `GitAccountSwitcher-v${version}-macOS.dmg.sha256`
- optional `docs/release-notes/v${version}.md`

Sparkle `generate_appcast` invocation stays the same: it already accepts `.dmg` assets under `release/` and will point `enclosure` URLs at the DMG when ZIP is absent.

## Documentation And Tests

Update:

- README install/release instructions to open the DMG and drag the app to Applications,
- any release notes / design text that hard-codes `.zip` for the current distribution format,
- `GitAccountSwitcherCoreTestRunner` string-contract tests that currently assert `.zip` paths in build/publish scripts.

## Out Of Scope

- Branded DMG window backgrounds, icon positioning, or custom Finder layout `.DS_Store` polish.
- Developer ID signing and notarization.
- Migrating or rewriting historical appcast entries that still point at older ZIP files.
- Publishing both ZIP and DMG.

## Success Criteria

- Tag release builds produce a `.dmg` + `.sha256` and no release ZIP.
- Public channel `release/` contains the DMG for the new version.
- Generated `appcast.xml` enclosure URL ends with `.dmg`.
- Opening the DMG shows the app and an Applications shortcut suitable for drag-install.
- Existing verification commands still pass: `swift run GitAccountSwitcherCoreTestRunner` and `swift build`.
