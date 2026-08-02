# Contributing to Switch Commit

Thanks for your interest in Switch Commit — a local-only macOS menu bar app and
`switch-commit` CLI for switching Git identities globally and per folder.

Please read this guide before opening a pull request. By participating, you also
agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before You Start

1. Search [existing issues](https://github.com/kwiats/switch-commit/issues) for
   duplicates.
2. For bugs and feature ideas, open an issue first when the change is
   non-trivial. Use the issue templates under `.github/ISSUE_TEMPLATE/` when
   they are available.
3. Security vulnerabilities must **not** be reported in public issues — see
   [SECURITY.md](SECURITY.md).

## Repository Layout

| Path | Role |
|---|---|
| `Sources/SwitchCommitCore/` | Pure core logic (models, config generation, persistence, safe writes, diagnostics) |
| `Sources/SwitchCommitAppLogic/` | UI-facing view model and presentation state |
| `Sources/SwitchCommitApp/` | SwiftUI/AppKit menu bar app, settings, Sparkle, launch-at-login |
| `Sources/SwitchCommitCLI/` | `switch-commit` CLI |
| `Sources/SwitchCommitCoreTestRunner/` | Local executable test runner (not XCTest) |
| `Scripts/` | Release, checks, and landing-site tooling |
| `site/` | Public landing page and Sparkle appcast (changelog sync from root `CHANGELOG.md`) |
| `CHANGELOG.md` | Single source of truth for release notes |
| `LICENSE.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md` | License and community / support docs |

Keep AppKit/SwiftUI out of `SwitchCommitCore`. Prefer deterministic, pure
functions in core and reuse core services from the CLI instead of duplicating
logic.

## Development Environment

- Swift 6.2 package targeting macOS 14+
- Work from an isolated Git worktree under `.worktrees/` (gitignored), branched
  from up-to-date `main` / `origin/main`

Branch names use Conventional Commit prefixes plus kebab-case:

- `feat/…`, `fix/…`, `chore/…`, `docs/…`

Example: `feat/folder-live-context`.

## Required Verification

From the repository root (or active worktree root), run:

```bash
swift run SwitchCommitCoreTestRunner
swift build
```

Do not assume `swift test` works. This project uses
`SwitchCommitCoreTestRunner` because the available Command Line Tools install
may not expose XCTest or Swift Testing modules.

Optional local check script:

```bash
Scripts/pr-checks.sh
```

## Safety Invariants (Non-Negotiable)

Contributions must preserve these constraints:

- **No secrets in JSON** profile files, generated Git config, logs, previews, or
  CLI output — only metadata and Keychain **references**.
- **No wholesale replace** of user-owned `~/.gitconfig` or `~/.ssh/config`
  (surgical `insteadOf` conflict removal in `~/.gitconfig` after backup is
  allowed).
- **No telemetry**, analytics, crash upload, or unrelated background product
  network calls.
- Menu bar Sparkle update checks only after explicit **Check for Updates**, and
  only against the public Switch Commit release channel.
- CLI update notices / `switch-commit update` may contact only that same public
  channel (12-hour cache for opportunistic notices).
- Managed writes stay under app-owned paths
  (`~/.config/git-account-switcher/`, `~/.ssh/git-account-switcher.conf`).
- SSH/GitHub diagnostics stay user-triggered, not automatic network probes.

## What Not to Commit

- Do **not** stage or commit `docs/superpowers/specs/` or
  `docs/superpowers/plans/` — those are local agent design/plan artifacts only.
- Do not commit secrets, Keychain payloads, Sparkle private keys, or local
  `dist/` artifacts.
- Prefer focused diffs; update `README.md` and root `CHANGELOG.md` when
  user-facing behavior changes.

## Pull Requests

1. Keep changes focused on one concern.
2. Fill out the pull request template under `.github/pull_request_template.md`
   when it is available.
3. Include verification evidence (`swift run SwitchCommitCoreTestRunner` and
   `swift build`).
4. Prefer draft PRs until the change is ready for review.
5. Use a clear Conventional Commit style subject (for example
   `fix: repair CLI symlink after update check`).

## Getting Help

- Product behavior and safety contract: [README.md](README.md)
- Vulnerability reporting: [SECURITY.md](SECURITY.md)
- User support channels: [SUPPORT.md](SUPPORT.md)
- Local diagnostics: `switch-commit doctor` (local Git/config checks only)
