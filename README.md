# Git Account Switcher

Local-only macOS menu bar tool for switching Git identities globally and per folder.

## Safety Contract

- No telemetry.
- No analytics.
- No automatic network calls.
- Manual update checks contact the public GitPersona release channel only after the user clicks `Check for Updates`.
- No secrets in JSON profile files.
- Managed writes are constrained to app-owned config files.
- `~/.gitconfig` only receives explicit include lines for managed Git config files.
- SSH/GitHub checks are manual diagnostics only.
- Host connection status updates only after the user clicks `Test Connection`; no connection checks run in the background.
- Existing `~/.gitconfig` and `~/.ssh/config` are never replaced wholesale.

### Manual Updates

GitPersona uses a public release channel for update metadata and signed app artifacts. The source repository can remain private because the app never downloads updates from the private repository and never embeds GitHub tokens.

The app checks for updates only when the user clicks `Check for Updates` in Settings. Update artifacts must be signed before publication, and Sparkle verifies the downloaded update before installation.

### Local GitHub Discovery

Git Account Switcher can suggest a GitHub account from local-only signals such as GitHub CLI configuration, global Git identity, SSH configuration, and GitHub remotes in a folder selected by the user.

Discovery does not call the GitHub API, does not log in to GitHub, does not read token values into app data, and does not scan the home directory automatically. A detected account is only a suggestion until the user imports it as a profile.

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

## Development

```bash
Scripts/pr-checks.sh
swift run GitAccountSwitcherCoreTestRunner
swift build
```

This repository currently uses a local test runner because the available Command Line Tools install does not expose XCTest or Swift Testing modules.
