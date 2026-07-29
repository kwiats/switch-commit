# AGENTS.md

## Project Context

Git Account Switcher is a local-only macOS menu bar app for switching Git identities globally and per folder. The app is implemented as a Swift Package using Swift 6.2 and targets macOS 14.

The project is intentionally privacy-preserving:

- no telemetry, analytics, crash upload, auto-update, or background network calls;
- no secrets in JSON profile files or generated Git config;
- manual diagnostics only for SSH/Git checks;
- existing `~/.gitconfig` and `~/.ssh/config` must never be replaced wholesale.

## Repository Layout

- `Package.swift`: Swift package manifest.
- `Sources/GitAccountSwitcherCore/`: pure core logic for models, config generation, persistence, safe writes, diagnostics, and Keychain abstractions.
- `Sources/GitAccountSwitcherAppLogic/`: UI-facing view model and presentation state.
- `Sources/GitAccountSwitcherApp/`: SwiftUI/AppKit menu bar app and settings window.
- `Sources/GitAccountSwitcherCoreTestRunner/`: local test runner used instead of XCTest or Swift Testing.
- `docs/superpowers/specs/`: design notes.
- `docs/superpowers/plans/`: implementation plans.
- `docs/release-notes/`: release notes.

## Build And Test

Use these commands from the repository root:

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
```

This repository currently uses `GitAccountSwitcherCoreTestRunner` because the available Command Line Tools installation does not expose XCTest or Swift Testing modules. Do not add XCTest-based tests unless the toolchain constraint has been verified again.

## Safety Invariants

Preserve these constraints in every change:

- `ProfileStore` persists metadata and Keychain references only, never secret payloads.
- `SafeFileWriter` must reject writes outside configured managed roots.
- Managed Git files live under `~/.config/git-account-switcher/`.
- Managed SSH include content lives at `~/.ssh/git-account-switcher.conf`.
- User-owned `~/.gitconfig` and `~/.ssh/config` may only receive explicit include lines after backup logic is in place.
- Diagnostics may run local commands through injected runners, but must not make network checks automatically.

## Implementation Guidance

- Prefer deterministic, pure functions in `GitAccountSwitcherCore`.
- Keep AppKit and SwiftUI concerns out of the core target.
- Keep shelling out isolated behind `CommandRunning`.
- Use `Sendable` where public model and service types cross UI or concurrency boundaries.
- Keep generated config stable and easy to diff.
- Use app-owned identifiers for Keychain references, for example `git-account-switcher.<profile-id>.<purpose>`.

## Documentation Guidance

- Keep user-facing docs focused on local safety, managed files, and commands.
- Keep planning docs in ASCII unless an existing file clearly uses non-ASCII text.
- When behavior changes, update `README.md` and relevant release notes or plan/spec files.

