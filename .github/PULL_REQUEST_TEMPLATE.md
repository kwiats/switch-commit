## Summary

<!-- What does this PR change and why? -->

## Test plan

- [ ] `swift run SwitchCommitCoreTestRunner`
- [ ] `swift build`
- [ ] Manual checks relevant to this change (describe below)

<!-- Additional verification steps: -->

## Safety checklist

- [ ] No secrets, tokens, passwords, or private keys persisted in JSON, Git config, logs, previews, or generated files
- [ ] No wholesale replacement of `~/.gitconfig` or `~/.ssh/config` (surgical include / insteadOf remediation only where already allowed)
- [ ] No telemetry, analytics, crash upload, or unrelated background product network calls
- [ ] Menu bar Sparkle checks remain explicit `Check for Updates` only; CLI update notices stay on the public release channel with existing cache rules

## Docs / changelog

- [ ] User-facing behavior changed → README and/or release notes updated
- [ ] No user-facing behavior change → N/A
