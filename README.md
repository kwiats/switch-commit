# Switch Commit

Local-only macOS menu bar tool for switching Git identities globally and per folder.

## Safety Contract

- No telemetry.
- No analytics.
- No broad automatic network calls.
- Manual update checks contact the public Switch Commit release channel only after the user clicks `Check for Updates`.
- No secrets in JSON profile files.
- Managed writes are constrained to app-owned config files.
- `~/.gitconfig` only receives explicit include lines for managed Git config files.
- SSH/GitHub discovery and diagnostics remain manual.
- Host connection status updates after the user clicks `Test Connection` and after the user switches the active SSH profile.
- Persisted host connection status stores only host names, status, messages, and timestamps; it does not store secrets.
- Launch at login is opt-in and controlled from Settings.
- Existing `~/.gitconfig` and `~/.ssh/config` are never replaced wholesale.

### Manual Updates

Switch Commit uses a public release channel for update metadata and signed app artifacts. The source repository can remain private because the app never downloads updates from the private repository and never embeds GitHub tokens.

The app checks for updates only when the user clicks `Check for Updates` in Settings. Update artifacts must be signed before publication, and Sparkle verifies the downloaded update before installation.

### Local GitHub Discovery

Switch Commit can suggest a GitHub account from local-only signals such as GitHub CLI configuration, global Git identity, SSH configuration, and GitHub remotes in a folder selected by the user.

Discovery does not call the GitHub API, does not log in to GitHub, does not read token values into app data, and does not scan the home directory automatically. A detected account is only a suggestion until the user imports it as a profile.

Profiles use an explicit access method: SSH or HTTPS. SSH profiles generate a managed `core.sshCommand` and can run an SSH connection test. HTTPS profiles rely on local Git credentials or GitHub CLI-configured credentials and do not require an SSH key.

## Managed Files

The app is designed to manage only these paths:

```text
~/.config/git-account-switcher/
~/.config/git-account-switcher/profiles/
~/.config/git-account-switcher/global.gitconfig
~/.config/git-account-switcher/rules.gitconfig
~/.ssh/git-account-switcher.conf
```

When existing files must be touched, the core file writer creates backups before replacement and rejects writes outside configured managed roots.

Switching the global profile from the menu writes the selected Git identity to:

```text
~/.config/git-account-switcher/global.gitconfig
```

Folder assignments write per-profile Git config under `~/.config/git-account-switcher/profiles/` and a shared rules file at `~/.config/git-account-switcher/rules.gitconfig`.

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

## Folder Account Assignments

Open **Settings → Accounts**, select an account, and use the **Folders** section to assign folders to that profile:

- **Folder tree** applies the profile to the selected folder and everything beneath it.
- **Single repo** applies the profile only to that one repository directory.
- Click **+** to pick a folder; remove an assignment with the trash button.
- If a path is already assigned to another account, Switch Commit asks before moving the rule.

Assignments are stored in profile metadata only. Saving settings regenerates managed Git config; no secrets are written to JSON.

## Automatic Git Identity per Folder

When folder rules exist, Switch Commit writes `~/.config/git-account-switcher/rules.gitconfig` with Git `includeIf "gitdir:..."` blocks that point at per-profile config files under `~/.config/git-account-switcher/profiles/`.

Git resolves `user.name`, `user.email`, and SSH profile settings from repository location automatically. You do not need to switch the global profile from the menu bar when working inside an assigned folder.

The app adds managed include lines to `~/.gitconfig` when they are missing:

```text
~/.config/git-account-switcher/global.gitconfig
~/.config/git-account-switcher/rules.gitconfig
```

To confirm Git is using the expected identity inside a repo:

```bash
git config --includes --show-origin user.name
git config --includes --show-origin user.email
```

## Live Folder Context and Menu Bar Preview

The menu bar title and the first menu item preview the profile that would apply in the frontmost supported application:

- Supported apps: Finder, Terminal, iTerm2, Cursor, and VS Code.
- The app polls about every two seconds.
- When a folder rule matches, the title shows `Profile · ~/path` and the menu header shows `Context: /path → Profile`.
- When no rule matches, the preview falls back to the global active profile (`Context: Global → Profile`).
- When the frontmost app is unsupported, the preview also shows the global active profile.

This is display-only. Live folder context never switches the global active profile; Git identity still comes from `includeIf` rules.

Folder discovery is local-only and never scans the home directory automatically.

## macOS Automation Permission

Reading the current folder from Finder, Terminal, or iTerm2 uses AppleScript. macOS may prompt for **Automation** permission under **System Settings → Privacy & Security → Automation**.

If permission is denied or a supported app's folder cannot be read, the menu bar shows `Context: unavailable (...)` and keeps the global profile name in the title. Git folder rules continue to work through `includeIf` regardless of Automation permission.

## Host Connection Check

The settings window shows a provider icon and connection status for each account:

- red: connection has not been tested, or no usable host is configured,
- orange: the latest test reported an SSH or local configuration problem,
- green: the latest test succeeded for every host in the profile.

Click `Test Connection` in the selected account header to run the SSH check. Switching the active profile from the menu bar also refreshes the switched SSH profile in the background, so profile status stays current across profile changes and app restarts.

## Launch at Login

Open Settings, choose `General`, and switch `Launch at Login` on or off. The app uses macOS Login Items registration and does not modify shell startup files.

## CLI

Switch Commit ships a `switch-commit` command-line tool that shares the same profile store and managed Git/SSH config as the menu bar app.

### Install

Two ways to put `switch-commit` on your PATH at `/usr/local/bin/switch-commit`:

1. **DMG installer package:** Open the release DMG and run `Install Switch Commit.pkg`. This installs the app to `/Applications` and places a launcher at `/usr/local/bin/switch-commit` that runs the bundled CLI inside the app bundle.
2. **Settings → General → Install CLI:** After copying the app to Applications, open Settings and click **Install CLI** (or **Reinstall CLI**). This creates a symlink from `/usr/local/bin/switch-commit` to `Switch Commit.app/Contents/MacOS/switch-commit`. macOS may prompt for administrator privileges when `/usr/local/bin` is not writable.

For local development:

```bash
swift build --product switch-commit
.build/debug/switch-commit --help
```

### Command cheat sheet

| Command | Description |
|---|---|
| `switch-commit` | Interactive profile menu when run on a TTY; prints usage on non-TTY |
| `switch-commit list` / `ls` | List profiles; active profile is marked |
| `switch-commit status` | Active global profile plus folder context for the current directory or `--path` |
| `switch-commit use <name\|id>` | Switch the global active profile and apply managed Git/SSH config |
| `switch-commit show <name\|id>` | Show profile metadata (no Keychain secret values) |
| `switch-commit add ...` | Create a profile |
| `switch-commit edit <name\|id> ...` | Update profile fields |
| `switch-commit delete <name\|id>` | Delete a profile (confirm interactively or pass `--yes`) |
| `switch-commit folder list` | List folder rules |
| `switch-commit folder add <path> --profile <name\|id>` | Assign a profile to a folder |
| `switch-commit folder remove <path\|id>` | Remove a folder rule |
| `switch-commit doctor` | Inspect the local Git identity at the current directory or `--path` |

Run `switch-commit help <command>` for flags and examples.

### Output flags

- `--json` — emit machine-readable JSON on stdout with stable field names. Secret payloads are never included.
- `--no-color` — disable ANSI color output. The CLI also respects the `NO_COLOR` environment variable.

Global flags apply to subcommands, for example `switch-commit list --json`.

### Broken symlink repair

If you delete or move `Switch Commit.app` without uninstalling the package, `/usr/local/bin/switch-commit` may point to a missing executable. Reinstall the app, then either run `Install Switch Commit.pkg` again or open Settings → General and click **Reinstall CLI**.

If another file already occupies `/usr/local/bin/switch-commit` and it is not a symlink, the installer reports the conflict. Remove or rename that file before reinstalling.

### Safety

The CLI follows the same safety contract as the app:

- no telemetry, analytics, or background network calls;
- profile JSON and CLI output show metadata and Keychain reference identifiers only — never tokens, passwords, or private key contents;
- `doctor` runs local Git and config checks only; it does not probe hosts over the network;
- managed writes stay under app-owned paths; user `~/.gitconfig` and `~/.ssh/config` are never replaced wholesale.

## Development

```bash
Scripts/pr-checks.sh
swift run SwitchCommitCoreTestRunner
swift build
```

This repository currently uses a local test runner because the available Command Line Tools install does not expose XCTest or Swift Testing modules.

## Release Build

Create a distributable macOS installer DMG:

```bash
Scripts/build-release.sh 0.2.5
```

The release artifacts are written to `dist/v0.2.5/`:

```text
SwitchCommit-v0.2.5-macOS.dmg
SwitchCommit-v0.2.5-macOS.dmg.sha256
release-url.txt
```

Install by opening the DMG and dragging `Switch Commit.app` to Applications.

## Release Channel CD

Pushing a version tag publishes Releases and Sparkle metadata in this same public repository:

```bash
git tag v0.2.0
git push origin v0.2.0
```

The tag workflow builds the DMG, creates a GitHub Release on `kwiats/switch-commit`, regenerates a latest-only `site/appcast.xml`, and writes `site/version.txt`. A separate `release: published` workflow syncs `site/index.html` changelog + download CTA from Releases. GitHub Pages deploys from `site/` via Actions. The app reads update metadata from:

```text
https://kwiats.github.io/switch-commit/appcast.xml
```

Configure this repository secret before tagging a release:

```text
SPARKLE_PRIVATE_ED_KEY
```

`SPARKLE_PRIVATE_ED_KEY` must match the `SUPublicEDKey` embedded by `Scripts/build-release.sh`. Repository `GITHUB_TOKEN` is enough for Releases and `site/` commits.

Export the Sparkle private key from the local Keychain before setting `SPARKLE_PRIVATE_ED_KEY`:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x /tmp/sparkle-private-key.txt
cat /tmp/sparkle-private-key.txt
rm /tmp/sparkle-private-key.txt
```

Use the exact contents printed by `cat` as the secret value. Do not use the public SUPublicEDKey value, the Info.plist XML snippet, the `/tmp/...` file path, or `SPARKLE_PRIVATE_ED_KEY=...` assignment text.

Generated appcast and landing download URLs point at GitHub Releases, for example:

```text
https://github.com/kwiats/switch-commit/releases/download/v0.2.5/SwitchCommit-v0.2.5-macOS.dmg
```

Bridge note for existing 0.2.x installs: publish `v0.3.0` with the new `SUFeedURL`, then run `Scripts/publish-legacy-bridge-appcast.sh 0.3.0` so the legacy channel appcast advertises that build. After `v0.3.1` ships on this repo, the legacy `switch-commit-release-channel` repository can be archived/removed.