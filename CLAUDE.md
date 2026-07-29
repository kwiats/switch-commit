# CLAUDE.md

## Working In This Repo

This repository contains Git Account Switcher, a Swift 6.2 macOS 14 menu bar app for safely switching Git identities. Treat it as a local-first security-sensitive tool.

Before editing, inspect the relevant source files and preserve the existing split:

- Core logic belongs in `Sources/GitAccountSwitcherCore/`.
- UI state belongs in `Sources/GitAccountSwitcherAppLogic/`.
- Menu bar and settings UI belong in `Sources/GitAccountSwitcherApp/`.
- Focused executable tests belong in `Sources/GitAccountSwitcherCoreTestRunner/`.

## Required Commands

Run these before claiming a change is complete:

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
```

Do not assume `swift test` works here. The current project intentionally uses a local executable test runner because XCTest and Swift Testing are unavailable in the installed Command Line Tools environment.

## Non-Negotiable Safety Rules

- Do not add telemetry, analytics, background network calls, crash upload, or auto-update behavior.
- Do not persist tokens, passwords, or credential payloads in JSON, Git config, logs, previews, or generated files.
- Keep secret storage behind Keychain abstractions.
- Do not replace the user's full `~/.gitconfig` or `~/.ssh/config`.
- Writes must stay constrained to app-managed paths and should keep backup behavior intact.
- SSH and GitHub checks must be explicit user-triggered diagnostics, not automatic probes.

## Current Architecture Notes

- `GitProfile`, `FolderRule`, and `ProfileStoreData` define persisted metadata.
- `ProfileStore` writes sorted, pretty JSON and stores only credential references.
- `GitConfigGenerator` creates profile config, root include config, and folder-rule include config.
- `SSHConfigGenerator` creates managed SSH identity blocks.
- `SafeFileWriter` creates parent directories, backs up existing files, and rejects unmanaged write targets.
- `DiagnosticsService` inspects local Git identity via injected `CommandRunning`.
- `AppViewModel` currently provides preview profile state, menu actions, diagnostics text, and settings presentation requests.

## Style Preferences

- Keep changes small and aligned with existing Swift style.
- Prefer plain Foundation and SwiftUI/AppKit APIs already in use.
- Add comments only when they clarify a non-obvious safety or platform decision.
- Keep generated output deterministic so tests and diffs stay stable.
- Update docs when commands, safety behavior, managed paths, or user-visible flows change.

