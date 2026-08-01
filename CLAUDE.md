# CLAUDE.md

## Working In This Repo

This repository contains Switch Commit, a Swift 6.2 macOS 14 menu bar app for safely switching Git identities, plus a `switch-commit` CLI. Treat it as a local-first security-sensitive tool.

Before editing, inspect the relevant source files and preserve the existing split:

- Core logic belongs in `Sources/SwitchCommitCore/`.
- UI state belongs in `Sources/SwitchCommitAppLogic/`.
- Menu bar, settings, Sparkle, and launch-at-login belong in `Sources/SwitchCommitApp/`.
- CLI belongs in `Sources/SwitchCommitCLI/`.
- Focused executable tests belong in `Sources/SwitchCommitCoreTestRunner/`.

## Required Commands

Run these before claiming a change is complete:

```bash
swift run SwitchCommitCoreTestRunner
swift build
```

Do not assume `swift test` works here. The current project intentionally uses a local executable test runner because XCTest and Swift Testing are unavailable in the installed Command Line Tools environment.

## Default Task Workflow

Unless the user explicitly asks for a different flow, handle implementation tasks end to end:

- Always work in an isolated Git worktree under `.worktrees/` (gitignored). Branch from up-to-date `main` / `origin/main`.
- Name branches with Conventional Commit prefixes: `feat/`, `fix/`, `chore/`, or `docs/`, plus kebab-case (for example `docs/update-agent-guides`).
- Inspect relevant files before editing and keep changes focused on the requested behavior.
- Local specs/plans may live under `docs/superpowers/specs/` and `docs/superpowers/plans/`, but never commit them.
- Run `swift run SwitchCommitCoreTestRunner` and `swift build` before claiming the work is complete.
- Commit completed product work with a clear Conventional Commit message after verification passes.
- Push the branch to the repository remote.
- Open a pull request for the pushed branch, using draft status unless the user asks for a ready PR.
- If verification or publishing cannot be completed, report the blocker and the exact command or step that failed.

## Non-Negotiable Safety Rules

- Do not add telemetry, analytics, crash upload, or unrelated background product network calls.
- Menu bar Sparkle update checks are allowed only after an explicit user `Check for Updates`, and only against the public release channel.
- The `switch-commit` CLI may query that same public appcast on a 12-hour TTL to warn about newer releases, and must contact the channel on `switch-commit update`.
- Do not persist tokens, passwords, or credential payloads in JSON, Git config, logs, previews, or generated files.
- Keep secret storage behind Keychain abstractions.
- Do not replace the user's full `~/.gitconfig` or `~/.ssh/config`; surgical insteadOf conflict removal in `~/.gitconfig` after backup is allowed.
- Writes must stay constrained to app-managed paths (plus the surgical gitconfig remediation above) and should keep backup behavior intact.
- SSH and GitHub checks must be explicit user-triggered diagnostics, not automatic probes.

## Current Architecture Notes

- `GitProfile`, `FolderRule`, and `ProfileStoreData` define persisted metadata, including access method and folder assignments.
- `ProfileStore` writes sorted, pretty JSON and stores only credential references.
- `GitConfigGenerator` creates profile config, root include config, and folder-rule include config.
- `SSHConfigGenerator` creates managed SSH identity blocks.
- `SafeFileWriter` creates parent directories, backs up existing files, and rejects unmanaged write targets.
- `FolderRuleResolver` / path normalizers pick the most specific enabled folder rule for a path.
- `GitHubLocalDiscoveryService` suggests accounts from local-only signals; import remains user-confirmed.
- `DiagnosticsService` inspects local Git identity via injected `CommandRunning`.
- `AppViewModel` owns menu/settings presentation, profile actions, folder context, diagnostics text, and connection-status UI state.
- `SwitchCommitCLI` exposes profile, folder, status, and doctor commands through ArgumentParser on top of core services.

## Style Preferences

- Keep changes small and aligned with existing Swift style.
- Prefer plain Foundation and SwiftUI/AppKit APIs already in use.
- Add comments only when they clarify a non-obvious safety or platform decision.
- Keep generated output deterministic so tests and diffs stay stable.
- When behavior changes, update `README.md` and release notes — not committed specs or plans.
