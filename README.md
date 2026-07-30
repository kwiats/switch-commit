# Git Account Switcher

Local-only macOS menu bar tool for switching Git identities globally and per folder.

## Safety Contract

- No telemetry.
- No analytics.
- No automatic network calls.
- Manual update checks contact the public Switch Commit release channel only after the user clicks `Check for Updates`.
- No secrets in JSON profile files.
- Managed writes are constrained to app-owned config files.
- `~/.gitconfig` only receives explicit include lines for managed Git config files.
- SSH/GitHub checks are manual diagnostics only.
- Host connection status updates only after the user clicks `Test Connection`; no connection checks run in the background.
- Launch at login is opt-in and controlled from Settings.
- Existing `~/.gitconfig` and `~/.ssh/config` are never replaced wholesale.

### Manual Updates

Switch Commit uses a public release channel for update metadata and signed app artifacts. The source repository can remain private because the app never downloads updates from the private repository and never embeds GitHub tokens.

The app checks for updates only when the user clicks `Check for Updates` in Settings. Update artifacts must be signed before publication, and Sparkle verifies the downloaded update before installation.

### Local GitHub Discovery

Git Account Switcher can suggest a GitHub account from local-only signals such as GitHub CLI configuration, global Git identity, SSH configuration, and GitHub remotes in a folder selected by the user.

Discovery does not call the GitHub API, does not log in to GitHub, does not read token values into app data, and does not scan the home directory automatically. A detected account is only a suggestion until the user imports it as a profile.

Profiles use an explicit access method: SSH or HTTPS. SSH profiles generate a managed `core.sshCommand` and can run a manual SSH connection test. HTTPS profiles rely on local Git credentials or GitHub CLI-configured credentials and do not require an SSH key.

## Managed Files

The app is designed to manage only these paths:

```text
~/.config/git-account-switcher/
~/.ssh/git-account-switcher.conf
```

When existing files must be touched, the core file writer creates backups before replacement and rejects writes outside configured managed roots.

Switching the global profile from the menu writes the selected Git identity to:

```text
~/.config/git-account-switcher/global.gitconfig
```

The app adds include lines to `~/.gitconfig` when they are missing, after backing up any existing file to `~/.config/git-account-switcher/backups/`.

## Manual Global Switch Check

1. Check the current global identity:

```bash
git config --includes --show-origin user.name
git config --includes --show-origin user.email
```

2. Switch accounts from the menu bar profile list.

3. Confirm Git now resolves the selected profile:

```bash
git config --includes --show-origin user.name
git config --includes --show-origin user.email
cat ~/.config/git-account-switcher/global.gitconfig
```

## Manual Host Connection Check

The settings window shows a provider icon and connection status for each account:

- red: connection has not been tested or no usable host is configured,
- orange: a manual test was attempted but SSH or local configuration reported a problem,
- green: the latest manual test succeeded for every host in the profile.

Click `Test Connection` in the selected account header to run the SSH check. The app never starts these network checks automatically.

## Launch at Login

Open Settings, choose `General`, and switch `Launch at Login` on or off. The app uses macOS Login Items registration and does not modify shell startup files.

## Development

```bash
Scripts/pr-checks.sh
swift run GitAccountSwitcherCoreTestRunner
swift build
```

This repository currently uses a local test runner because the available Command Line Tools install does not expose XCTest or Swift Testing modules.

## Release Build

Create a distributable macOS app ZIP:

```bash
Scripts/build-release.sh 0.1.1
```

The release artifacts are written to `dist/v0.1.1/`:

```text
GitAccountSwitcher-v0.1.1-macOS.zip
GitAccountSwitcher-v0.1.1-macOS.zip.sha256
release-url.txt
```

Install by unzipping the archive and moving `Git Account Switcher.app` to `Applications`.

## Release Channel CD

Pushing a version tag publishes the public Sparkle release channel:

```bash
git tag v0.2.0
git push origin v0.2.0
```

The tag workflow builds the app, copies the ZIP/checksum/release notes into `kwiats/switch-commit-release-channel/release/`, regenerates `appcast.xml`, and pushes the public channel repository. The app reads update metadata from:

```text
https://kwiats.github.io/switch-commit-release-channel/appcast.xml
```

Configure these source-repository secrets before tagging a release:

```text
RELEASE_CHANNEL_TOKEN
SPARKLE_PRIVATE_ED_KEY
```

`RELEASE_CHANNEL_TOKEN` needs write access to the public release channel repository. `SPARKLE_PRIVATE_ED_KEY` must match the `SUPublicEDKey` embedded by `Scripts/build-release.sh`.

Export the Sparkle private key from the local Keychain before setting `SPARKLE_PRIVATE_ED_KEY`:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x /tmp/sparkle-private-key.txt
cat /tmp/sparkle-private-key.txt
rm /tmp/sparkle-private-key.txt
```

Use the exact contents printed by `cat` as the secret value. Do not use the public SUPublicEDKey value, the Info.plist XML snippet, the `/tmp/...` file path, or `SPARKLE_PRIVATE_ED_KEY=...` assignment text.

Generated appcast download URLs point at the public release folder, for example:

```text
https://kwiats.github.io/switch-commit-release-channel/release/GitAccountSwitcher-v0.2.0-macOS.zip
```
