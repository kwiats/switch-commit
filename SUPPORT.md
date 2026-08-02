# Support

## Where to Get Help

| Need | Where |
|---|---|
| How Switch Commit works, safety contract, CLI reference | [README.md](README.md) |
| Bug reports and feature requests | [GitHub Issues](https://github.com/kwiats/switch-commit/issues) |
| Contributing / development setup | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Security vulnerabilities | [SECURITY.md](SECURITY.md) (private reporting only) |
| Downloads and release notes | [GitHub Releases](https://github.com/kwiats/switch-commit/releases) and the [landing page](https://kwiats.github.io/switch-commit/) |
| Community conduct concerns | [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) |

## Before Opening an Issue

1. Confirm you are on a current release (`switch-commit version`, or Settings →
   Check for Updates).
2. Reproduce with local diagnostics when possible:

```bash
switch-commit doctor
switch-commit status
switch-commit doctor --path /path/to/repo
```

`doctor` inspects local Git identity and managed config only; it does **not**
probe hosts over the network. For SSH connectivity, use **Test Connection** in
Settings (user-triggered).

3. Redact secrets. Share metadata, paths, and Keychain reference identifiers —
   never private keys, tokens, or passwords.
4. Include macOS version, Switch Commit / CLI version, and whether the problem is
   in the menu bar app, CLI, folder rules, or updates/install.

## Product Support Expectations

Switch Commit is distributed as a free download from the public GitHub release
channel. There is **no paid support plan** and **no guaranteed response SLA**.

Maintainers review GitHub issues as capacity allows. Useful reports include
reproduction steps, expected vs actual behavior, and sanitized diagnostic
output.

Community answers on issues are welcome; please stay within the
[Code of Conduct](CODE_OF_CONDUCT.md).

## What Maintainers Typically Cannot Do

- Remotely inspect or repair your machine
- Accept production credentials or private keys for debugging
- Promise timelines for feature work
- Provide legal advice about Git identity, employer policy, or trademark use

## Updates and Installation Help

- Menu bar: Settings → **Check for Updates**
- CLI: `switch-commit update`
- Broken CLI symlink: Settings → General → **Reinstall CLI**, or run
  `switch-commit update` after the app is installed in `/Applications`

See the README sections on CLI install and broken symlink repair for details.
