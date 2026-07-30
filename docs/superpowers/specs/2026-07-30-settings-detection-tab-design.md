# Settings Detection Tab Design

## Goal

Make local account detection readable when the settings window is short by moving detection out of the account edit form and into its own settings tab.

## UX

Settings uses two tabs:

- `Accounts`: keeps the existing account sidebar, selected account header, edit fields, access reset, status message, and diagnostics footer.
- `Detection`: shows detection controls and detected account suggestions with enough vertical space for scrolling.

The detection tab includes:

- a title and short local-only safety note;
- buttons for detecting local GitHub accounts and scanning a selected folder;
- a scrollable results list;
- provider and source labels for each suggestion;
- confidence, warning, and import action controls.

## Source Labels

Detected accounts already expose `provider` and `sources`. The UI maps those values to readable labels:

- `github` -> `GitHub`
- `githubCliHostsFile` -> `GitHub CLI`
- `githubCliInstalled` -> `GitHub CLI`
- `globalGitConfig` -> `Global Git config`
- `gitCredentialUsername` -> `Git credentials`
- `sshConfig` -> `SSH config`
- `sshResolvedConfig` -> `SSH resolved config`
- `repositoryRemote` -> `Repository remote`

## Scope

No discovery behavior changes. No new network calls. No persistence changes. This is a focused settings UI update.

## Verification

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
```
