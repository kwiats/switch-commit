# GitPersona Manual Updates Design

## Goal

Add a customer-facing update path for GitPersona while preserving the app's local-first privacy model. Source code remains in a private repository. Public distribution uses a separate release channel that hosts only signed application artifacts, update metadata, and release notes.

The first version of this feature should support manual update checks only. The app must not check for updates automatically at launch, on a timer, or in the background.

## Product Name

The customer-facing product name is `GitPersona`.

The current package and module names can remain `GitAccountSwitcher` until a separate rename plan exists. User-facing release materials, update copy, and public distribution assets should use `GitPersona`.

## Release Channel

Use a separate public GitHub repository as the update channel. The exact repository name can be chosen during release setup, but it should be customer-facing and aligned with the product name, for example:

```text
gitpersona-release-channel
```

The public repository contains only distribution assets:

- Sparkle appcast metadata,
- signed `.zip` or `.dmg` application artifacts,
- release notes,
- checksums or detached verification files if needed by the release workflow.

The public repository must not contain source code, secrets, private configuration, GitHub tokens, signing keys, or build credentials.

## Update Mechanism

Use Sparkle as the macOS update framework. Sparkle should be configured for manual update checks first:

- the user clicks `Check for Updates`,
- the app contacts the public appcast URL,
- Sparkle compares the installed version with the latest published version,
- Sparkle downloads and verifies the signed update artifact,
- Sparkle handles install and relaunch prompts.

Automatic background update checks are out of scope for the first version.

## UI

Add an `Updates` area in Settings. This can be a dedicated tab or a compact section depending on the final settings layout.

The UI should show:

- product name: `GitPersona`,
- installed version,
- `Check for Updates` button,
- short privacy note explaining that update checks contact the public release channel only after the user clicks,
- optional `Release Notes` link.

The menu bar app should not show update notifications unless Sparkle is responding to a user-initiated check.

## Privacy And Safety

The feature must preserve these invariants:

- no telemetry,
- no analytics,
- no crash upload,
- no GitHub tokens embedded in the app,
- no secrets in profile files,
- no automatic network calls,
- update network access happens only after the user clicks `Check for Updates`.

The README safety contract should be updated to make the manual update exception explicit: GitPersona performs an update request only when the user asks it to check for updates.

## Private Repository Handling

The app must not access the private source repository at runtime. It must not use GitHub API tokens, GitHub CLI credentials, or browser session state to download updates.

Private repository access remains a build and release concern only. The release workflow builds the app from the private repository, signs the artifact, generates appcast metadata, and publishes only public distribution assets to the release channel repository.

## Signing And Verification

Updates must be signed before publication. Sparkle verification is the trust boundary for downloaded updates.

Release setup should decide whether distribution uses:

- Developer ID signing plus notarization,
- Sparkle EdDSA signing,
- both, if required for the final packaging flow.

The implementation should avoid shipping update installation behavior until the signing flow is documented and tested with a sample release artifact.

## Error Handling

User-visible update errors should be plain and actionable:

- no internet connection,
- release channel unavailable,
- no update available,
- downloaded update failed signature verification,
- update installation cancelled.

Errors must not expose tokens because the app does not use runtime tokens for updates.

## Testing

Core update URL and presentation decisions should be testable without network access. App logic tests should cover:

- installed version presentation,
- manual update check button wiring,
- privacy copy for manual network access,
- disabled or placeholder state when Sparkle is not configured for a local debug build.

Manual release verification should cover:

- appcast can be fetched from the public release channel,
- Sparkle detects a newer version,
- downloaded artifact passes signature verification,
- cancelled update leaves the current app intact,
- failed verification blocks installation.

## Out Of Scope

- automatic background update checks,
- embedding GitHub tokens,
- reading GitHub CLI credentials,
- downloading from the private source repository at runtime,
- full product rename across package, modules, bundle IDs, and docs,
- in-app release publishing or release management.
