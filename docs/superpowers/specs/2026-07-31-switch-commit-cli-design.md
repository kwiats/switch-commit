# Switch Commit CLI Design

## Goal

Ship a first-class command-line interface for Switch Commit so users can list and switch Git identities, manage profiles and folder rules, run local diagnostics, and automate workflows with stable `--json` output — without opening the menu bar UI.

The binary is invoked as `switch-commit`.

## Status

Approved for implementation planning after brainstorming (2026-07-31).

## Background

- Product backlog item: `docs/future-features.md` section 3 (CLI).
- Folder-accounts design explicitly deferred CLI to a separate task.
- `SwitchCommitCore` already owns profiles, folder rules, managed Git/SSH config generation, safe writes, diagnostics, and Keychain abstractions.
- Menu bar app and CLI must share the same on-disk store and managed paths; no secrets in JSON or generated config.

## Decisions

| Topic | Choice |
|---|---|
| Scope (v1) | Full management: read + switch + profile CRUD + folder rules + local doctor + `--json` |
| Interaction | Hybrid: subcommands for scripting; no-args on a TTY opens interactive profile menu |
| Packaging | Binary inside the `.app`; `.pkg` in DMG installs app + CLI to PATH; Settings also offers Install / Reinstall CLI |
| Presentation | Structured ANSI color for commands; simple TUI panel for interactive mode |
| Language | English (aligned with app UI / README) |
| Architecture | SPM executable + `swift-argument-parser` + small custom ANSI/TUI renderer on top of `SwitchCommitCore` (no XPC, no heavy TUI framework) |

## Architecture

### Targets

- New executable product/target: `switch-commit` → `Sources/SwitchCommitCLI/`.
- Depends on `SwitchCommitCore` and `swift-argument-parser`.
- Does **not** depend on `SwitchCommitApp`, `SwitchCommitAppLogic`, AppKit, or Sparkle.
- Shared persistence: same `ProfileStore` paths and managed roots as the app (`~/.config/git-account-switcher/`, `~/.ssh/git-account-switcher.conf`).

### Runtime model

- CLI is standalone: works whether or not the menu bar app is running.
- Mutations go through core APIs (`ProfileStore`, profile/folder managers, `ManagedGitConfigInstaller` / equivalent), never ad-hoc writes outside managed roots.
- No IPC/XPC to the GUI in v1.
- No telemetry, analytics, crash upload, auto-update, or background network.
- Diagnostics (`doctor`) stay local-only unless the user explicitly opts into a network-touching check that already exists as an explicit user action in the app model (if exposed at all in CLI v1, it must remain opt-in and documented). Prefer mirroring existing local diagnostics first.

### Packaging and install

1. Release build embeds `switch-commit` inside `SwitchCommit.app` (e.g. `Contents/MacOS/switch-commit` or `Contents/Resources/bin/switch-commit`).
2. Distribution installer: **`.pkg` wrapped in the existing DMG flow** installs:
   - app → `/Applications/SwitchCommit.app`
   - CLI onto PATH via `/usr/local/bin/switch-commit` (symlink or thin wrapper pointing into the app bundle).
3. Settings → General (or dedicated CLI row): **Install CLI** / **Reinstall CLI** creates or refreshes the `/usr/local/bin/switch-commit` link (admin prompt when required). Covers drag-only `.app` installs and repair.
4. Uninstall of the pkg should remove the PATH entry; deleting only the `.app` may leave a broken symlink — Install/Reinstall and docs explain repair.

Developer workflow remains `swift build` / `swift run switch-commit`.

## Command surface

Binary name: `switch-commit`.

### Global flags

- `--json` — machine-readable stdout; no ANSI; stable field names; never includes secret payloads.
- `--no-color` — disable ANSI even on TTY.
- Respect `NO_COLOR` when set.
- `--help` / `-h`, `version` / `--version`.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | User / validation error (unknown profile, bad args, cancelled) |
| `2` | System / I/O / config apply failure |

### Commands

| Command | Behavior |
|---|---|
| *(no args, TTY)* | Interactive profile picker (see UX) |
| *(no args, non-TTY)* | Print short help on stderr and exit `1` (never hang waiting for input) |
| `list` / `ls` | List profiles; mark active |
| `status` | Resolved identity: global active + optional folder context for `cwd` or `--path` |
| `use <name\|id>` | Switch global active profile and apply managed Git/SSH config |
| `show <name\|id>` | Profile details (metadata only; no Keychain secret values) |
| `add` | Create profile (flags and/or interactive prompts) |
| `edit <name\|id>` | Update profile fields |
| `delete <name\|id>` | Delete profile (confirm unless `--yes`) |
| `folder list` | List folder rules |
| `folder add <path> --profile <name\|id> [--mode folder-tree\|single-repo]` | Add/move rule (confirm on takeover) |
| `folder remove <path\|id>` | Remove rule |
| `doctor` | Local Git/SSH/config diagnostics via injected/local command runners; no automatic network |

Profile identity resolution accepts display name (case-insensitive unique match) or id; ambiguous names error with candidates.

### Core gaps to fill during implementation

If missing today, add focused core APIs (not CLI-only file edits):

- Folder rule CRUD + path normalize + longest-prefix resolve (align with folder-accounts design / `FolderRuleResolver` if present).
- Non-UI-oriented profile create/update helpers suitable for CLI flags (or thin wrappers over `ProfileSettingsManager` without AppLogic).

## UX and output

### Human (TTY)

- Structured color: accent for active marker, muted labels, green/red for success/failure.
- Stable column/label layout so output is skimmable and diff-friendly in screenshots/docs.
- No emoji requirement; simple glyphs (`●`, `✓`, `❯`) are fine where terminals support them; ASCII fallbacks when needed.

### Interactive mode

When `switch-commit` runs with no args on a TTY:

- Panel titled `switch-commit · profiles`.
- List profiles with email subtitle; active marked.
- Keys: ↑↓ move, Enter = `use`, `a` add flow, `d` delete (with confirm), `q` quit.
- v1 is a **simple** list UI (custom ANSI), not a full-screen app framework.

### JSON

- One JSON object (or array for lists) on stdout.
- Errors with `--json`: emit a single JSON object on stdout, `{"ok":false,"error":"..."}`, and exit non-zero. Without `--json`: human message on stderr, empty stdout, non-zero exit.
- Never print tokens, private key material, or Keychain secret payloads.

### Errors

- Short actionable message on stderr for humans.
- Do not stack-trace by default.
- Preserve safety copy: managed roots, backups, no wholesale `~/.gitconfig` / `~/.ssh/config` replace.

## Safety

- Same invariants as the app: no secrets in profile JSON, logs, previews, or generated Git/SSH config.
- `SafeFileWriter` managed-root rejection remains in force.
- CLI must not introduce telemetry or background network.
- HTTPS credential refs may be shown as identifiers only.
- Destructive actions (`delete`, folder takeover) require confirmation unless `--yes`.

## Testing

Extend `SwitchCommitCoreTestRunner` (or a small CLI-focused suite invoked from the same runner) for:

- command parsing / routing pure helpers where extracted,
- human and JSON formatters (deterministic strings),
- profile use / CRUD / folder rule mutations against temp directories and fake stores,
- exit-code mapping for common failures,
- guarantee JSON fixtures contain no secret-like fields.

Interactive TUI: minimal smoke or skip full keyboard automation in v1.

Required verification before claiming done:

```bash
swift run SwitchCommitCoreTestRunner
swift build
```

## Documentation

- README: install PATH behavior (pkg + Settings), command cheat sheet, `--json` note, safety reminder.
- `docs/future-features.md` section 3 → implemented / partially implemented as work lands.
- Release notes when shipping.
- Update release/DMG/pkg scripts docs when installer gains CLI install steps.

## Out of scope (v1)

- Homebrew formula (may follow later).
- XPC to the running menu bar app.
- Heavy TUI frameworks / full lazygit-style UI.
- Automatic network probes from `doctor`.
- Localized (non-English) CLI strings.
- Windows/Linux.
- Replacing the menu bar app.

## Implementation notes

- Work on an isolated git worktree and `codex/` branch.
- Prefer deterministic pure helpers in Core or CLI for formatting and resolution.
- Keep `SwitchCommitCLI` free of AppKit/SwiftUI.
- Installer changes must not weaken existing Sparkle/manual-update privacy guarantees.

## Open follow-ups (post-v1)

- Homebrew cask/formula.
- Richer TUI (multi-pane folder browser).
- Shell completions (zsh/bash/fish).
