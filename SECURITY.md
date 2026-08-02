# Security Policy

Switch Commit is a local-first Git identity switcher. Security reports that
protect users' Git config, SSH setup, and Keychain-referenced credentials are
especially welcome.

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Please report privately using GitHub Security Advisories:

https://github.com/kwiats/switch-commit/security/advisories/new

If advisory filing is unavailable, contact the maintainer privately via GitHub
([@kwiats](https://github.com/kwiats)) and clearly mark the message as a
security report.

### What to include

- A clear description of the issue and impact
- Affected component (menu bar app, `switch-commit` CLI, config generation,
  installers/update path, etc.)
- Steps to reproduce, preferably with a minimal local reproduction
- Switch Commit / CLI version (`switch-commit version`) and macOS version when
  relevant

### What not to include

- Do **not** attach real SSH private keys, tokens, passwords, Keychain secret
  payloads, or production credentials.
- Prefer redacted config snippets and Keychain **reference identifiers** only
  (for example `git-account-switcher.<profile-id>.<purpose>`).
- Do not share secrets beyond what is strictly needed to understand the issue.

## Scope

**In scope**

- Switch Commit menu bar app
- `switch-commit` CLI
- Profile persistence and Keychain reference handling
- Managed Git/SSH config generation and safe file writes
- Update/install paths that touch the public Switch Commit release channel
  (Sparkle appcast, DMG install, CLI symlink repair)
- Accidental secret leakage into JSON, logs, previews, or generated config

**Out of scope**

- Issues solely in third-party tools (Git, OpenSSH, Sparkle as upstream,
  GitHub CLI) that are not caused by Switch Commit's integration
- Compromised user machines, stolen local credentials, or phishing unrelated to
  this project
- Social-engineering reports without a product vulnerability
- Feature requests filed as security issues (use normal issues instead)
- Denial-of-service against the public landing page / appcast hosting alone,
  unless it enables a Switch Commit-specific compromise path

## Project Security Expectations

Switch Commit aims to:

- Persist metadata and Keychain references only — never secret payloads in
  profile JSON or generated Git config
- Avoid telemetry, analytics, and unrelated background product network calls
- Contact the public release channel only for explicit menu-bar update checks
  and CLI update notices / `switch-commit update`
- Never replace `~/.gitconfig` or `~/.ssh/config` wholesale
- Keep diagnostics local unless the user explicitly runs a connection test

## Response Expectations

There is no paid security SLA. Maintainers aim to:

1. Acknowledge a private report when capacity allows (often within several days)
2. Confirm whether the report is in scope and reproducible
3. Work on a fix in a private or draft branch when needed
4. Credit reporters in release notes if desired (opt-out available)

Response times vary with severity and maintainer availability. Critical issues
that can leak credentials or overwrite user Git/SSH config outside managed
paths are prioritized.

## Safe Local Diagnostics

For non-sensitive troubleshooting, prefer:

```bash
switch-commit doctor
switch-commit status
switch-commit show <profile>
```

These commands are designed to avoid printing secret payloads. If output still
looks sensitive, redact before sharing in public issues.
