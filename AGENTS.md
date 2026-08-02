# AGENTS.md

## Project Context

Switch Commit is a local-only macOS menu bar app for switching Git identities globally and per folder. The app is implemented as a Swift Package using Swift 6.2 and targets macOS 14. It also ships a `switch-commit` CLI.

The product is a **paid** macOS app (intended retail price about **$2.50**). It remains privacy-first and local-only: there is no in-app telemetry, analytics, or payment/backend network stack in this repository. Treat pricing as product positioning for docs and support copy; do not invent purchase-provider or license-server details that are not implemented in code.

The project is intentionally privacy-preserving:

- no telemetry, analytics, crash upload, or other background product network calls;
- menu bar Sparkle update checks run only after an explicit `Check for Updates`;
- the `switch-commit` CLI may contact the public Switch Commit release channel (Sparkle appcast) on a 12-hour cache TTL to surface security/update notices, and always on `switch-commit update`;
- no secrets in JSON profile files or generated Git config;
- manual diagnostics only for SSH/Git checks;
- existing `~/.gitconfig` and `~/.ssh/config` must never be replaced wholesale (surgical insteadOf conflict removal in `~/.gitconfig` is allowed after backup).

## Repository Layout

### Product / source

- `Package.swift`: Swift package manifest.
- `Sources/SwitchCommitCore/`: pure core logic for models, config generation, persistence, safe writes, diagnostics, discovery, and Keychain abstractions.
- `Sources/SwitchCommitAppLogic/`: UI-facing view model and presentation state.
- `Sources/SwitchCommitApp/`: SwiftUI/AppKit menu bar app, settings window, Sparkle wiring, and launch-at-login.
- `Sources/SwitchCommitCLI/`: `switch-commit` command-line interface.
- `Sources/SwitchCommitCoreTestRunner/`: local test runner used instead of XCTest or Swift Testing.
- `Scripts/`: release, checks, and landing-site tooling.
- `site/`: public landing page and Sparkle appcast (landing changelog sync reads root `CHANGELOG.md`).

### Community / governance (repo root)

- `LICENSE.md`: project license.
- `CODE_OF_CONDUCT.md`: community conduct expectations.
- `CONTRIBUTING.md`: how to contribute, verify, and open PRs.
- `SECURITY.md`: private vulnerability reporting.
- `SUPPORT.md`: where users get help; product is paid (~$2.50), community Issues for bugs, no support SLA.
- `CHANGELOG.md`: **single source of truth** for release notes (site landing syncs from this file via `Scripts/site-landing`).

### GitHub templates and CI

- `.github/ISSUE_TEMPLATE/`: issue forms — `bug_report.yml`, `feature_request.yml`, `custom.md`, plus `config.yml`.
- `.github/PULL_REQUEST_TEMPLATE.md`: pull request template.
- `.github/`: also CI workflows and Dependabot.

### Local agent artifacts only

- `docs/superpowers/specs/` and `docs/superpowers/plans/`: local agent design/plan artifacts only — never commit these.

Do **not** reintroduce `docs/release-notes/`; that path was consolidated into root `CHANGELOG.md`.

## Build And Test

Use these commands from the repository root (or the active worktree root):

```bash
swift run SwitchCommitCoreTestRunner
swift build
```

This repository currently uses `SwitchCommitCoreTestRunner` because the available Command Line Tools installation does not expose XCTest or Swift Testing modules. Do not add XCTest-based tests unless the toolchain constraint has been verified again.

## Default Task Workflow

Unless the user explicitly asks for a different flow, handle implementation tasks end to end:

- Always work in an isolated Git worktree under `.worktrees/` (must stay gitignored). Create the worktree from up-to-date `main` / `origin/main`.
- Use Conventional Commit branch prefixes: `feat/`, `fix/`, `chore/`, or `docs/`, followed by a short kebab-case description (for example `feat/folder-live-context`).
- Inspect relevant files before editing and keep changes focused on the requested behavior.
- Specs and implementation plans may be written under `docs/superpowers/specs/` and `docs/superpowers/plans/` for local use, but never stage or commit them.
- Run `swift run SwitchCommitCoreTestRunner` and `swift build` before claiming the work is complete.
- Commit completed product work with a clear Conventional Commit message after verification passes.
- Push the branch to the repository remote.
- Open a pull request for the pushed branch, using draft status unless the user asks for a ready PR.
- If verification or publishing cannot be completed, report the blocker and the exact command or step that failed.

## Safety Invariants

Preserve these constraints in every change:

- `ProfileStore` persists metadata and Keychain references only, never secret payloads.
- `SafeFileWriter` must reject writes outside configured managed roots.
- Managed Git files live under `~/.config/git-account-switcher/`.
- Managed SSH include content lives at `~/.ssh/git-account-switcher.conf`.
- User-owned `~/.gitconfig` and `~/.ssh/config` must never be replaced wholesale; `~/.gitconfig` may receive explicit include lines and surgical removal of conflicting unmanaged `insteadOf` keys after backup.
- Diagnostics may run local commands through injected runners, but must not make network checks automatically.
- Menu bar Sparkle update checks contact only the public Switch Commit release channel after explicit `Check for Updates`.
- CLI update notices/`switch-commit update` may contact only that same public release channel (appcast + release assets), with opportunistic checks cached for 12 hours.

## Implementation Guidance

- Prefer deterministic, pure functions in `SwitchCommitCore`.
- Keep AppKit and SwiftUI concerns out of the core target.
- Keep CLI parsing and presentation in `SwitchCommitCLI`; reuse core services instead of duplicating logic.
- Keep shelling out isolated behind `CommandRunning`.
- Use `Sendable` where public model and service types cross UI or concurrency boundaries.
- Keep generated config stable and easy to diff.
- Prefer small, focused diffs aligned with existing Swift style.
- Prefer plain Foundation and SwiftUI/AppKit APIs already in use.
- Add comments only when they clarify a non-obvious safety or platform decision.
- Use app-owned identifiers for Keychain references, for example `git-account-switcher.<profile-id>.<purpose>`.

## Documentation Guidance

- Keep user-facing docs focused on local safety, managed files, CLI commands, and release behavior.
- When behavior changes, update `README.md` and root `CHANGELOG.md` (not a separate release-notes directory).
- Point contributors and support seekers at `CONTRIBUTING.md`, `SECURITY.md`, and `SUPPORT.md` as appropriate.
- Do not commit specs, plans, brainstorming notes, or other agent-process artifacts.
