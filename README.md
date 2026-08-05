# Switch Commit

Local-only macOS menu bar tool for switching Git identities globally and per folder.

## Buy / soft paywall

The landing page offers **Buy & Download** via [Polar](https://polar.sh) (Merchant of Record) at a **$1** launch price (compare-at **$2.50**). After payment, Polar delivers the DMG through File Downloads.

GitHub Releases DMG assets remain public (soft paywall) — the free secondary link on the landing still points at the latest release asset. Paid delivery is updated automatically on each version tag: `Scripts/polar-sync-dmg.mjs` uploads the DMG and refreshes the Polar downloadables benefit.

**Release operators must configure:**

| Name | Where | Purpose |
| --- | --- | --- |
| `POLAR_ACCESS_TOKEN` | GitHub Actions secret | Polar API token (`files:write`, benefits write) |
| `POLAR_ORGANIZATION_ID` | GitHub Actions secret | Polar organization UUID |
| `POLAR_BENEFIT_ID` | GitHub Actions secret | Downloadables benefit UUID |
| `POLAR_CHECKOUT_URL` | GitHub Actions variable (public) | Stable Checkout Link used by the landing Buy button |

Local landing sync:

```bash
export POLAR_CHECKOUT_URL='https://buy.polar.sh/your-checkout-link'
node Scripts/site-landing/sync-landing.mjs
```

**Polar Checkout Link → Success URL** (after payment):

```text
https://kwiats.github.io/switch-commit/thanks.html
```

Optional with session id: `https://kwiats.github.io/switch-commit/thanks.html?checkout_id={CHECKOUT_ID}`

## Safety Contract

- No telemetry.
- No analytics.
- No broad automatic product network calls.
- Menu bar update checks contact the public Switch Commit release channel only after the user clicks `Check for Updates` (and then sync/repair the CLI symlink to the app bundle).
- The `switch-commit` CLI may contact that same public channel on a 12-hour cache to print an update notice, and always on `switch-commit update` (download + install app + repair CLI + restart a running menu bar app when possible).
- No secrets in JSON profile files.
- Managed writes are constrained to app-owned config files.
- `~/.gitconfig` receives explicit include lines for managed Git config files and may have conflicting unmanaged `url.*.insteadOf` keys removed after backup when they oppose the active profile.
- SSH/GitHub discovery and diagnostics remain manual.
- Host connection status updates after the user clicks `Test Connection` and after the user switches the active SSH profile.
- Persisted host connection status stores only host names, status, messages, and timestamps; it does not store secrets.
- Launch at login is opt-in and controlled from Settings.
- Existing `~/.gitconfig` and `~/.ssh/config` are never replaced wholesale.

### Manual Updates

Switch Commit uses a public release channel for update metadata and signed app artifacts. The source repository can remain private because the app never downloads updates from the private repository and never embeds GitHub tokens.

The menu bar app checks for updates only when the user clicks `Check for Updates` in Settings. Update artifacts must be signed before publication, and Sparkle verifies the downloaded update before installation. After a successful check (an update was installed, or the app is already up to date), Switch Commit also repairs `/usr/local/bin/switch-commit` so it points at the CLI bundled inside the updated app (macOS may prompt for administrator privileges).

The CLI reads `https://kwiats.github.io/switch-commit/appcast.xml` (cached for 12 hours) so any `switch-commit` command can print when a newer release exists. Run `switch-commit update` to refresh live, download the DMG (SHA-256 verified when the companion `.sha256` asset exists), install `Switch Commit.app` into `/Applications`, repair `/usr/local/bin/switch-commit`, and restart a running Switch Commit menu bar app when possible.

### Local GitHub Discovery

Switch Commit can suggest a GitHub account from local-only signals such as GitHub CLI configuration, global Git identity, SSH configuration, and GitHub remotes in a folder selected by the user.

Discovery does not call the GitHub API, does not log in to GitHub, does not read token values into app data, and does not scan the home directory automatically. A detected account is only a suggestion until the user imports it as a profile.

Profiles use an explicit access method: SSH or HTTPS. SSH profiles generate a managed `core.sshCommand` and can run an SSH connection test. HTTPS profiles rely on local Git credentials or GitHub CLI-configured credentials and do not require an SSH key.

For each configured host, Switch Commit also writes Git `url.<base>.insteadOf` rules so transport follows the profile access method without rewriting remotes in `.git/config`:

- SSH profiles rewrite `https://HOST/` and `ssh://git@HOST/` to `git@HOST:` (then use the profile SSH key).
- HTTPS profiles rewrite `git@HOST:` and `ssh://git@HOST/` to `https://HOST/`.

## Managed Files

The app is designed to manage only these paths:

```text
~/.config/git-account-switcher/
~/.config/git-account-switcher/profiles/
~/.config/git-account-switcher/global.gitconfig
~/.config/git-account-switcher/rules.gitconfig
~/.ssh/git-account-switcher.conf
```

When existing files must be touched, the core file writer creates backups before replacement and rejects writes outside configured managed roots. Identical rewrites skip the backup and write, and backup filenames include a UUID so concurrent reapply cannot collide.

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

Assignments are stored in profile metadata only. Saving settings regenerates managed Git config; no secrets are written to JSON. The same assignments can be managed with `switch-commit folder add` / `folder remove`; Settings reloads them when you open the window or the app becomes active.

## Automatic Git Identity per Folder

When folder rules exist, Switch Commit writes `~/.config/git-account-switcher/rules.gitconfig` with Git `includeIf "gitdir:..."` blocks that point at per-profile config files under `~/.config/git-account-switcher/profiles/`.

Git resolves `user.name`, `user.email`, SSH command, and `url.insteadOf` transport rewrites from repository location automatically. You do not need to switch the global profile from the menu bar when working inside an assigned folder, and you do not need to manually change `https://` remotes to `git@` when the folder profile uses SSH.

The app adds managed include lines to `~/.gitconfig` when they are missing:

```text
~/.config/git-account-switcher/global.gitconfig
~/.config/git-account-switcher/rules.gitconfig
```

To confirm Git is using the expected identity inside a repo:

```bash
git config --includes --show-origin user.name
git config --includes --show-origin user.email
switch-commit doctor
```

`doctor` warns when a folder profile’s access method differs from the global profile, because both sets of `url.insteadOf` rules can be active at once.

Starting the app or any `switch-commit` CLI command rewrites managed Git config from the current profiles and folder rules, so generator updates (such as new `url.insteadOf` output) apply without a manual profile switch.

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

### Global flags

These flags work on the root command and every subcommand:

- `--json` — emit machine-readable JSON on stdout with stable field names. Secret payloads are never included.
- `--no-color` — disable ANSI color output.
- The CLI also respects the `NO_COLOR` environment variable.

Examples: `switch-commit list --json`, `switch-commit status --path ~/Dev/acme --no-color`.

Profile references accept a display name or id. Matching is case-insensitive for names; ambiguous names error with candidates. Run `switch-commit help <command>` for the live ArgumentParser help text.

### Commands

#### `switch-commit` (no arguments)

On a TTY, opens an interactive profile menu:

- ↑ / ↓ move, Enter = `use`, `a` add, `d` delete (with confirm), `q` quit.

On a non-TTY session, prints usage and exits without waiting for input.

```bash
switch-commit
```

#### `list` / `ls`

List configured profiles. The active profile is marked.

```bash
switch-commit list
switch-commit ls --json
```

#### `status`

Show the active global profile plus folder-rule context for the current directory, or for `--path`.

| Flag | Description |
|---|---|
| `--path <path>` | Path to inspect for a matching folder rule |

```bash
switch-commit status
switch-commit status --path ~/Dev/acme
```

#### `use`

Switch the global active profile and apply managed Git/SSH config.

```bash
switch-commit use work
switch-commit use <profile-id>
```

#### `show`

Show profile metadata (no Keychain secret values).

```bash
switch-commit show work
switch-commit show work --json
```

#### `add`

Create a profile.

| Flag | Description |
|---|---|
| `--name <name>` | Profile display name (required) |
| `--git-name <git-name>` | Git commit author name (required) |
| `--git-email <git-email>` | Git commit author email (required) |
| `--access <ssh\|https>` | Access method (default: `https`) |
| `--ssh-key <path>` | SSH private key path (required when `--access ssh`) |
| `--host <host>` | Git host; repeat for multiple hosts (default host: `github.com`) |
| `--https-credential-ref <ref>` | Keychain credential reference identifier |

```bash
switch-commit add \
  --name personal \
  --git-name "Ada Lovelace" \
  --git-email ada@example.com

switch-commit add \
  --name work \
  --git-name "Ada" \
  --git-email ada@acme.com \
  --access ssh \
  --ssh-key ~/.ssh/id_ed25519_work \
  --host github.com
```

#### `edit`

Update fields on an existing profile. Only provided flags change.

| Flag | Description |
|---|---|
| `--name <name>` | New display name |
| `--git-name <git-name>` | New Git author name |
| `--git-email <git-email>` | New Git author email |
| `--access <ssh\|https>` | Access method |
| `--ssh-key <path>` | SSH private key path |
| `--host <host>` | Replace the host list (repeat for multiple) |
| `--https-credential-ref <ref>` | Keychain credential reference identifier |

```bash
switch-commit edit work --git-email ada@new-acme.com
switch-commit edit work --access https --https-credential-ref git-account-switcher.work.https
```

#### `delete`

Delete a profile. Confirms interactively unless `--yes` is passed.

| Flag | Description |
|---|---|
| `--yes` | Delete without prompting |

```bash
switch-commit delete personal
switch-commit delete personal --yes
```

#### `folder list`

List folder-specific profile rules.

```bash
switch-commit folder list
switch-commit folder list --json
```

#### `folder add`

Assign a profile to a folder. Git `includeIf` rules are regenerated so identity and transport (`url.insteadOf`) apply automatically inside that path.

Path, profile, and mode are optional:

- path defaults to the current directory;
- profile defaults to the active global profile (`switch-commit use …`);
- mode defaults to `single-repo` when the path contains `.git`, otherwise `folder-tree`.

| Flag | Description |
|---|---|
| `--profile <name\|id>` | Profile to assign (default: active profile) |
| `--mode <folder-tree\|single-repo>` | Match mode (default: inferred from `.git`) |
| `--yes` | Take over an existing rule without prompting |

```bash
switch-commit folder add
switch-commit folder add .
switch-commit folder add ~/Dev/acme --profile work
switch-commit folder add ~/Dev/acme --profile work --mode folder-tree
switch-commit folder add ~/Dev/solo-repo --profile personal --mode single-repo
```

#### `folder remove`

Remove a folder rule by path or rule id.

| Flag | Description |
|---|---|
| `--yes` | Remove without prompting |

```bash
switch-commit folder remove ~/Dev/acme
switch-commit folder remove <rule-id> --yes
```

#### `doctor`

Inspect the local Git identity at the current directory or `--path`. Runs local Git/config checks only; it does not probe hosts over the network.

| Flag | Description |
|---|---|
| `--path <path>` | Path to inspect (default: current directory) |

```bash
switch-commit doctor
switch-commit doctor --path ~/Dev/acme --json
```

#### `update`

Check the public release channel live, download the latest DMG when newer than this CLI, install `Switch Commit.app` into `/Applications` (may prompt for admin), repair `/usr/local/bin/switch-commit`, and restart a running menu bar app when possible.

```bash
switch-commit update
switch-commit update --json
```

Other CLI commands may print an stderr notice when a newer release is known from the 12-hour appcast cache (suppressed with `--json`).

#### `version`

Print the CLI version.

```bash
switch-commit version
switch-commit version --json
```

### Broken symlink repair

If you delete or move `Switch Commit.app` without uninstalling the package, `/usr/local/bin/switch-commit` may point to a missing executable. Reinstall the app, then either run `Install Switch Commit.pkg` again, open Settings → General and click **Reinstall CLI**, or run `switch-commit update`.

**Reinstall CLI** / `switch-commit update` replace a stale non-symlink stub at `/usr/local/bin/switch-commit` (for example an old copied binary or package launch script) with a symlink to the bundled CLI.

### Safety

The CLI follows the same safety contract as the app:

- no telemetry or analytics;
- opportunistic update notices and `switch-commit update` contact only the public Switch Commit release channel;
- profile JSON and CLI output show metadata and Keychain reference identifiers only — never tokens, passwords, or private key contents;
- `doctor` runs local Git and config checks only; it does not probe hosts over the network;
- managed writes stay under app-owned paths; user `~/.gitconfig` and `~/.ssh/config` are never replaced wholesale (conflicting unmanaged `insteadOf` keys in `~/.gitconfig` may be removed after backup).

### Agent skill / plugin

Coding agents (Claude Code, Codex) can load a Switch Commit skill that knows safe CLI usage — inspect identity, switch profiles, and manage folder rules (not create/edit/delete profiles or `update`). See [agent-plugins/switch-commit/README.md](agent-plugins/switch-commit/README.md).

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

The tag workflow builds the DMG, creates a GitHub Release on `kwiats/switch-commit` from the matching `## [X.Y.Z]` section in root `CHANGELOG.md` (required), uploads that markdown as a Sparkle notes asset, regenerates `site/appcast.xml`, writes `site/version.txt`, and syncs `site/index.html` changelog (from `CHANGELOG.md`) + download CTA. Missing changelog entries fail the publish step. A separate `Sync landing` workflow remains for manual re-sync via `workflow_dispatch` or manually published releases. GitHub Pages deploys from `site/` via Actions. The app reads update metadata from:

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
