# Git Account Switcher

Local-only macOS menu bar tool for switching Git identities globally and per folder.

## Safety Contract

- No telemetry.
- No analytics.
- No automatic network calls.
- No secrets in JSON profile files.
- Managed writes are constrained to app-owned config files.
- SSH/GitHub checks are manual diagnostics only.
- Existing `~/.gitconfig` and `~/.ssh/config` are never replaced wholesale.

## Managed Files

The app is designed to manage only these paths:

```text
~/.config/git-account-switcher/
~/.ssh/git-account-switcher.conf
```

When existing files must be touched, the core file writer creates backups before replacement and rejects writes outside configured managed roots.

## Development

```bash
Scripts/pr-checks.sh
swift run GitAccountSwitcherCoreTestRunner
swift build
```

This repository currently uses a local test runner because the available Command Line Tools install does not expose XCTest or Swift Testing modules.
