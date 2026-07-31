# AGENTS.md

## Project Context

Switch Commit is a local-only macOS menu bar app for switching Git identities globally and per folder. The app is implemented as a Swift Package using Swift 6.2 and targets macOS 14.

The project is intentionally privacy-preserving:

- no telemetry, analytics, crash upload, auto-update, or background network calls;
- no secrets in JSON profile files or generated Git config;
- manual diagnostics only for SSH/Git checks;
- existing `~/.gitconfig` and `~/.ssh/config` must never be replaced wholesale.

## Repository Layout

- `Package.swift`: Swift package manifest.
- `Sources/SwitchCommitCore/`: pure core logic for models, config generation, persistence, safe writes, diagnostics, and Keychain abstractions.
- `Sources/SwitchCommitAppLogic/`: UI-facing view model and presentation state.
- `Sources/SwitchCommitApp/`: SwiftUI/AppKit menu bar app and settings window.
- `Sources/SwitchCommitCLI/`: command-line interface.
- `Sources/SwitchCommitCoreTestRunner/`: local test runner used instead of XCTest or Swift Testing.
- `Scripts/`: release, checks, and landing-site tooling.
- `site/`: public landing page and Sparkle appcast.
- `docs/release-notes/`: release notes.
- `.github/`: CI workflows and Dependabot.

## Build And Test

Use these commands from the repository root:

```bash
swift run SwitchCommitCoreTestRunner
swift build
```

This repository currently uses `SwitchCommitCoreTestRunner` because the available Command Line Tools installation does not expose XCTest or Swift Testing modules. Do not add XCTest-based tests unless the toolchain constraint has been verified again.

## Default Task Workflow

Unless the user explicitly asks for a different flow, handle implementation tasks end to end:

- Start each task from a dedicated Git branch using the `codex/` prefix.
- Inspect relevant files before editing and keep changes focused on the requested behavior.
- Run `swift run SwitchCommitCoreTestRunner` and `swift build` before claiming the work is complete.
- Commit completed work with a clear message after verification passes.
- Push the branch to the repository remote.
- Open a pull request for the pushed branch, using draft status unless the user asks for a ready PR.
- If verification or publishing cannot be completed, report the blocker and the exact command or step that failed.

## Safety Invariants

Preserve these constraints in every change:

- `ProfileStore` persists metadata and Keychain references only, never secret payloads.
- `SafeFileWriter` must reject writes outside configured managed roots.
- Managed Git files live under `~/.config/git-account-switcher/`.
- Managed SSH include content lives at `~/.ssh/git-account-switcher.conf`.
- User-owned `~/.gitconfig` and `~/.ssh/config` may only receive explicit include lines after backup logic is in place.
- Diagnostics may run local commands through injected runners, but must not make network checks automatically.

## Implementation Guidance

- Prefer deterministic, pure functions in `SwitchCommitCore`.
- Keep AppKit and SwiftUI concerns out of the core target.
- Keep shelling out isolated behind `CommandRunning`.
- Use `Sendable` where public model and service types cross UI or concurrency boundaries.
- Keep generated config stable and easy to diff.
- Use app-owned identifiers for Keychain references, for example `git-account-switcher.<profile-id>.<purpose>`.

## Documentation Guidance

- Keep user-facing docs focused on local safety, managed files, and commands.
- When behavior changes, update `README.md` and relevant release notes.
