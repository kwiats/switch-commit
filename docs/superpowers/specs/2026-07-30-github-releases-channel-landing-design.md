# GitHub Releases Channel Landing Design

## Goal

Move Switch Commit release artifacts out of GitHub Pages folders and onto GitHub Releases in the public channel repository. Keep Pages lean: landing page, version marker, and a latest-only Sparkle appcast. Clean up the mixed `release/` vs `releases/` directories.

## Decisions

- Host GitHub Releases in `kwiats/switch-commit-release-channel` (not the private source repo).
- Pages keeps only: `index.html`, `version.txt`, `appcast.xml`, plus `.nojekyll` / `README.md`.
- `appcast.xml` is latest-only (one Sparkle item for the tagged version).
- On each tag publish, write `version.txt` and regenerate `index.html` from a source-repo template (static HTML, no runtime JS fetch).
- One-time cleanup removes `release/` and `releases/` from the channel repo; CD never recreates them.
- Artifact remains the current DMG contract: `SwitchCommit-vX.Y.Z-macOS.dmg` (+ `.sha256`, optional notes).

## Release Channel Model

Public Pages base:

```text
https://kwiats.github.io/switch-commit-release-channel/
```

Files on Pages:

| Path | Role |
| --- | --- |
| `index.html` | Landing with latest version CTA |
| `version.txt` | Single line `X.Y.Z` (no leading `v`) |
| `appcast.xml` | Sparkle feed for the latest release only |

Download URL for assets:

```text
https://github.com/kwiats/switch-commit-release-channel/releases/download/vX.Y.Z/SwitchCommit-vX.Y.Z-macOS.dmg
```

`SUFeedURL` stays on Pages `appcast.xml`. The app must not depend on private source-repo URLs at runtime.

## Cross-Repo Split

Source repo (`git-account-switcher`) owns:

- tag workflow and publish scripts,
- canonical landing template at `docs/release-channel/index.html` with placeholders such as `__VERSION__` and `__DMG_URL__` / `__SHA256_URL__` (or equivalent stable markers),
- tests that lock the publish contract.

Channel repo (`switch-commit-release-channel`) receives generated outputs via the existing checkout + commit/push flow:

- GitHub Release `vX.Y.Z` + assets created with `gh` using `RELEASE_CHANNEL_TOKEN`,
- overwritten `appcast.xml`, `version.txt`, `index.html`,
- deletion of leftover `release/` and `releases/` directories on publish.

## Pipeline

On push of tag `vX.Y.Z`:

1. Validate semantic version tag.
2. Run `Scripts/pr-checks.sh`.
3. Run `Scripts/build-release.sh` to produce the DMG and checksum under `dist/vX.Y.Z/`.
4. Check out `kwiats/switch-commit-release-channel` with `RELEASE_CHANNEL_TOKEN`.
5. Create or update GitHub Release `vX.Y.Z` in the channel repo and upload DMG, checksum, and release notes when present.
6. Run Sparkle `generate_appcast` against a local staging copy of the DMG (not committed to Pages), with:

   ```text
   --download-url-prefix https://github.com/kwiats/switch-commit-release-channel/releases/download/vX.Y.Z/
   --versions X.Y.Z
   ```

   Write `appcast.xml` into the channel clone root.
7. Write `version.txt` containing `X.Y.Z`.
8. Render `docs/release-channel/index.html` into the channel clone `index.html` with the version and GitHub Releases URLs substituted.
9. Remove `release/` and `releases/` from the channel clone if present.
10. Commit and push the channel clone.

## Script Boundaries

`Scripts/build-release.sh`:

- keeps building the DMG bundle,
- documents/derives the public artifact URL as the GitHub Releases download URL (not a Pages folder path),
- keeps `SUFeedURL` on the Pages appcast.

`Scripts/publish-release-channel.sh`:

- creates/uploads the channel GitHub Release,
- generates latest-only appcast with the Releases download prefix,
- writes `version.txt`,
- renders the landing template into `index.html`,
- does not copy DMG/checksum into Pages folders,
- removes obsolete `release/` and `releases/` directories.

Workflow secrets stay:

- `RELEASE_CHANNEL_TOKEN` — fine-grained (or classic) token with write access to `kwiats/switch-commit-release-channel`, including Contents write so `git push` and `gh release create/upload` both succeed,
- `SPARKLE_PRIVATE_ED_KEY` — private EdDSA key for `generate_appcast` via stdin.

## One-Time Cleanup

Before or as part of the first publish after this change:

- delete `release/` and `releases/` from `switch-commit-release-channel`,
- optionally backfill older builds as GitHub Releases (nice-to-have; not required for CD).

## Testing

Extend `GitAccountSwitcherCoreTestRunner` contract checks:

- publish writes `version.txt` and renders `index.html` from `docs/release-channel/index.html`,
- appcast download prefix uses GitHub Releases URLs,
- publish/workflow uses `gh release` (or equivalent) against the channel repo,
- publish does not copy artifacts into `release/` or `releases/`,
- README documents Releases + `version.txt` + template rendering.

## Out Of Scope

- Multi-version Sparkle appcast history.
- Runtime JS fetch of `version.txt`.
- Moving Releases into the private source repository.
- Changing Sparkle public key / feed host.
