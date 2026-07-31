# SSH Key Context Menu - Design

## Goal

In Settings, when a profile uses SSH access, choosing an SSH key should not require typing a path into a free-text field. Clicking the SSH key control opens a menu of discovered local keys, with escape hatches for picking a file or entering a custom path.

This keeps identity switching local-only and privacy-preserving: discovery reads only local filesystem and SSH config files, never network probes.

## Scope

In scope:

- replace the SSH key `TextField` in Settings with a clickable menu control,
- discover private SSH key candidates from `~/.ssh` and `IdentityFile` entries in SSH config,
- support **Choose File...** via `NSOpenPanel`,
- support **Enter Path...** via an alert/sheet with a text field,
- persist selection through the existing `updateSelectedProfileSSHKeyPath` path,
- unit-test discovery/dedup/sort rules in `SwitchCommitCoreTestRunner`.

Out of scope:

- creating new SSH keys,
- uploading keys to GitHub,
- automatic SSH connection tests when selecting a key,
- changing HTTPS credential UX,
- replacing `~/.ssh/config` wholesale.

## Architecture

Add a pure discovery helper in `SwitchCommitCore`, for example `SSHKeyDiscovery`, that:

- accepts injectable home directory / file reading boundaries so tests can use temporary directories,
- returns a stable, deduplicated list of private key paths suitable for menu display,
- never shells out and never contacts the network.

`AppViewModel` exposes discovered keys to Settings (refresh when the SSH key row is shown or the menu opens). Settings UI in `SwitchCommitApp` owns presentation only: menu, open panel, enter-path alert.

Existing persistence and validation stay in `ProfileSettingsManager` / `GitProfile` (SSH profiles still reject empty key paths).

## Discovery Rules

Sources:

1. Regular files under `~/.ssh`.
2. `IdentityFile` values from `~/.ssh/config`.
3. `IdentityFile` values from `~/.ssh/git-account-switcher.conf` when that managed include exists.

Include:

- ordinary files that look like private keys (for example `id_ed25519`, `id_rsa`, custom names without `.pub`).

Exclude:

- directories,
- `*.pub`,
- `config`, `config.*`,
- `known_hosts`, `known_hosts.*`,
- `authorized_keys`, `authorized_keys.*`.

Normalization:

- expand leading `~` to the home directory for existence checks and dedup,
- store/display paths in a stable form preferred by the app (home-relative `~/...` when under home, otherwise absolute),
- deduplicate after normalization,
- sort by basename, then full path.

Missing `~/.ssh`, unreadable config, or empty results produce an empty list without throwing into the UI.

## UI And Interaction

Visible only when the selected profile access method is SSH.

Control:

- shows the current `sshKeyPath`, or a placeholder such as `Choose SSH key` when empty,
- left-click opens a SwiftUI `Menu` (popup).

Menu contents:

1. Discovered keys, each selectable; current selection shows a checkmark.
2. Separator.
3. **Choose File...** - opens `NSOpenPanel` starting near `~/.ssh` when possible.
4. **Enter Path...** - presents an alert/sheet with one text field, OK, and Cancel.

Behavior:

- selecting a discovered key, a panel file, or a confirmed entered path immediately calls `updateSelectedProfileSSHKeyPath`,
- Cancel in the panel or alert leaves the previous value unchanged,
- if discovery returns no keys, the menu still shows the two escape-hatch actions.

Enter Path is intentionally modal (alert/sheet), not an always-visible text field, so the common path stays menu-first and power-user typing stays focused.

## Error Handling

- Unreadable discovery inputs: empty list, no crash.
- Invalid entered path rejected by existing profile validation: keep previous value and surface a short settings message using the existing settings messaging pattern.
- Open panel cancel / alert cancel: no mutation.

## Testing

Add focused cases in `SwitchCommitCoreTestRunner`:

- temporary `.ssh` directory yields private keys and skips `.pub` / config junk,
- `IdentityFile` lines from config are included,
- managed include file contributes identity paths when present,
- duplicate paths across sources collapse to one entry,
- sort order is stable,
- missing directory returns an empty list.

UI wiring can stay thin; discovery correctness is the main automated coverage.

## Safety

- No telemetry, no background network, no secret payloads in JSON.
- Discovery never reads private key file contents into profile storage; only paths.
- User-owned `~/.gitconfig` and `~/.ssh/config` remain untouched by this feature (read-only for discovery).
