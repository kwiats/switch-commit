# Manual Host Connection Status Design

## Goal

Add visible host connection status for each account while preserving the app's local-first privacy model. The app must not run automatic network checks. A host connection check only runs when the user explicitly clicks `Test Connection`.

## Status Model

Each account has a presentation status derived from the latest manual host test results and local profile completeness:

- Red: not connected. This is the initial state before any manual test, or when no usable host can be tested.
- Orange: a manual test was attempted but failed, or the profile is locally incomplete or misconfigured enough that a connection test cannot run.
- Green: the latest manual test succeeded for every host in the selected profile.

For profiles with multiple hosts, the aggregate status is green only when all tested hosts succeed. One failed or untestable host makes the account orange after a test attempt.

## Manual Test Behavior

The `Test Connection` button runs SSH tests for the selected profile's hosts. The command should be created through core logic so it can be tested without tying the UI to shell details.

GitHub hosts use the common SSH target `git@github.com`. Other hosts use `git@<host>`. This avoids treating a plain hostname as a local SSH login target. The command uses batch mode so the app does not hang waiting for interactive password or passphrase prompts.

GitHub's successful SSH authentication message can return a non-zero exit code because GitHub does not provide shell access. The parser should treat output containing GitHub's successful authentication text as connected.

## UI

Use the approved option C:

- The account sidebar shows a provider icon and a small colored connection status dot for each profile.
- The selected account header shows a larger status indicator with text, plus a `Test Connection` button.
- The status text should explain the current state without requiring diagnostics text.
- Existing diagnostics remain manual and secondary.

Provider icon scope is intentionally small for this change. Profiles with `github.com` in their hosts show a GitHub-oriented icon. Other profiles show a generic Git provider icon.

## Persistence

Connection test results are runtime presentation state only. They are not written to `profiles.json` and do not include secret payloads.

## Safety

The feature must preserve these invariants:

- no automatic network checks,
- no telemetry or background calls,
- no secret storage in profile JSON,
- no replacement of user-owned Git or SSH config files,
- shell execution remains isolated behind injected command runners.

## Testing

Core tests cover:

- command construction for GitHub and non-GitHub hosts,
- GitHub success parsing even when the exit code is non-zero,
- failed command results becoming failed connection results,
- aggregate profile status for untested, failed, misconfigured, and connected profiles.

App logic tests cover:

- `Test Connection` updates selected profile status,
- sidebar-visible status can be queried for any profile,
- status results are runtime state and do not mutate profile metadata.
