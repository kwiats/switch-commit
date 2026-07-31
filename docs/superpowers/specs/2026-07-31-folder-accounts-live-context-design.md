# Folder Accounts + Live Context Design

## Goal

Let users assign Git accounts to folders, keep Git identity switching automatic via managed `includeIf` rules, show those folder assignments under each account in Settings (never as global usage), and continuously preview the resolved context in the menu bar based on the frontmost app (Finder, Terminal, iTerm, Cursor/VS Code).

## Status

Approved for implementation planning. CLI for folder rules is explicitly out of scope (separate future task).

## Background

- Core already has `FolderRule`, `GitConfigGenerator.rulesConfig`, and `ManagedGitConfigInstaller`.
- `ProfileSettingsManager` persists `rules` but has no Settings CRUD beyond deleting rules when a profile is deleted.
- Settings Accounts tab shows account fields only; no folder list.
- Menu bar shows active global profile only; no folder context.
- Product backlog item: `docs/future-features.md` section 4.

## Approach

### Switching identity (Git)

Folder identity continues to work through managed Git config:

1. User assigns folder path → profile via `FolderRule`.
2. Installer regenerates managed rules config with `includeIf "gitdir:..."`.
3. When the user runs Git inside a matching working tree, Git applies that profile's config automatically.
4. Changing frontmost focus never calls `git config` and never changes `activeProfileId`. Focus only updates the menu-bar preview.

### Resolving context (app)

`FrontmostContextMonitor` polls the frontmost application every ~2 seconds (local only, no network):

1. If frontmost is Terminal.app / iTerm2 / Cursor / VS Code → best-effort CWD.
2. If frontmost is Finder → active Finder folder path.
3. Otherwise → no folder context; preview shows the global active profile.

Priority is always **frontmost / focus**, not a fixed Terminal-over-Finder ranking.

Paths used for matching are normalized before compare: expand `~`, resolve to absolute form when possible, and strip a trailing `/` except for filesystem root. Matching considers only `enabled == true` rules.

`FolderRuleResolver` (pure core) maps a path + rules + active profile to:

- a matching enabled folder rule (most specific / longest matching prefix wins), or
- global active profile when no rule matches.

### Settings list

Under account form fields, a **Folders** section lists only `FolderRule` rows where `profileId` equals the selected account. Global active use is never listed there.

## Components

### SwitchCommitCore

- `FolderRule` / `FolderRuleMatchMode` — unchanged shape (`folderTree`, `singleRepo`).
- `FolderRuleResolver` — pure matching API for path → rule or global.
- `ProfileSettingsManager` — add rule CRUD:
  - list rules for a profile id,
  - add rule (default `matchMode = .folderTree`),
  - remove rule,
  - move/overwrite when the same path is already assigned to another profile (caller supplies confirmation),
  - persist + `ManagedGitConfigInstaller.apply` after mutations.

### SwitchCommitAppLogic

- `AppViewModel` presentation:
  - folder rows for selected profile,
  - add/remove/move folder actions,
  - live `contextPresentation` (path, profile display name, source, or unavailable reason),
  - menu content revision bumps when context or rules change.

### SwitchCommitApp

- `FrontmostContextMonitor` + path providers (Finder, Terminal, iTerm, Cursor/VS Code).
- Menu bar title/subtitle and top menu rows for context.
- Settings UI: Folders section under account detail.

## Data semantics

- One path maps to at most one rule.
- Default match mode: `folderTree` (path and descendants). UI toggle allows `singleRepo`.
- Overlapping trees: longest matching prefix wins.
- Assigning a path already owned by another profile requires confirmation; on confirm, the rule is moved (same path, new `profileId`), then config is reapplied.
- Deleting a profile still removes its rules (existing behavior).

## UI

### Settings → Accounts → selected account

Below Credentials:

- Section title: `Folders`
- Match-mode control (Folder tree default / Single repo) applies to the next add
- `+` opens directory picker and creates a rule with the selected mode
- List rows: all rules for this profile (including disabled, if any), path, mode badge, delete
- Empty copy: `No folder assignments`

### Menu bar

- Status item reflects live context, e.g. `Work · ~/Dev/acme` or global profile name when no folder rule matches.
- Menu header:
  - `Context: <path> → <profile>`
  - or `Context: Global → <profile>`
  - or `Context: unavailable` with short reason (Automation denied, unsupported app, etc.)
- Existing global profile switch list remains below.

## Permissions and degraded mode

- First Terminal/Finder automation may prompt macOS Automation permission.
- Denial or unsupported CWD sources must not crash: show unavailable/global fallback.
- Cursor/VS Code CWD is best-effort in v1; failure is non-fatal.
- No background network, telemetry, or Notification Center mismatch alerts in this scope.

## Out of scope

- CLI for profiles / folder rules (next user task)
- Importing external user-authored `includeIf` blocks from `~/.gitconfig`
- Notification Center alerts on identity mismatch
- Changing global active profile based on focus
- Continuous shell hooks

## Safety

- Preserve managed-path writes and backup behavior.
- Never replace wholesale `~/.gitconfig` / `~/.ssh/config`.
- No secrets in JSON, generated Git config, menu titles, or Settings folder lists.
- Context monitor only reads local frontmost path metadata.

## Testing

`SwitchCommitCoreTestRunner` covers:

- resolver: tree match, single-repo match, overlap specificity, no match → global,
- rule CRUD: add/remove/move between profiles; per-profile listing excludes global,
- generated rules config remains deterministic after mutations.

AppKit / Automation providers are not executed in the core runner; adapters are mockable at the AppLogic boundary where needed.

## Docs

- Update `docs/future-features.md` section 4 status toward implemented / partially implemented as work lands.
- README note: folder assignments, menu-bar context, and Automation permission expectation.
