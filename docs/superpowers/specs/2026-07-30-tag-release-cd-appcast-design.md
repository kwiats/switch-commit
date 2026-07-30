# Tag Release CD Appcast Design

## Goal

When a version tag such as `v0.2.0` is pushed, GitHub Actions should build the macOS app, update the public Switch Commit release channel, and publish the channel contents so Sparkle can read `appcast.xml` from GitHub Pages.

## Release Channel Model

Keep the current runtime URL model:

```text
https://kwiats.github.io/switch-commit-release-channel/appcast.xml
```

The public release channel repository is `kwiats/switch-commit-release-channel`. Its GitHub Pages branch should contain generated `appcast.xml` at the repository root and release assets under `release/`, including ZIP artifacts, checksums, optional Sparkle delta files, and release notes. The app must not point to the private source repository at runtime.

## Pipeline

The private source repository gets a tag-triggered workflow:

- trigger on tags matching `v*`,
- validate that the tag is semantic version shaped,
- run the existing test/build checks,
- run the release build script for the tag version,
- clone the public release channel repository,
- copy the new ZIP, checksum, and release notes into `release/` inside that clone,
- run Sparkle's `generate_appcast` against the `release/` assets directory and write `appcast.xml` at the release channel root,
- commit and push the public release channel update.

The workflow requires repository secrets:

- `RELEASE_CHANNEL_TOKEN`: token with write access to `kwiats/switch-commit-release-channel`,
- `SPARKLE_PRIVATE_ED_KEY`: private Sparkle EdDSA key, passed to `generate_appcast` through standard input.

## Script Boundaries

`Scripts/build-release.sh` remains responsible for producing a signed local `.app` bundle and ZIP artifact. It should centralize release channel URL values so `SUFeedURL` and artifact URL generation cannot drift apart.

`Scripts/publish-release-channel.sh` is responsible for publishing into an already checked-out release channel directory. It should reject missing artifacts, missing Sparkle signing key, malformed versions, and a missing `generate_appcast` tool.

## Testing

Use the existing `GitAccountSwitcherCoreTestRunner` to guard the release contract by reading scripts/workflows as text. Tests should verify:

- `build-release.sh` derives the appcast URL and `release/` artifact URL from the same public base URL,
- the publish script invokes Sparkle `generate_appcast` with `--ed-key-file -`,
- the tag workflow triggers only for `v*` tags and pushes to `kwiats/switch-commit-release-channel`,
- documentation lists the secrets and tag command.
