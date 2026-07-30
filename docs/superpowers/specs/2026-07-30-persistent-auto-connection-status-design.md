# Persistent Auto Connection Status Design

## Goal

Persist the latest connection test state for every tested profile and automatically refresh the newly active SSH profile after global profile switches.

## Status Persistence

Connection state is saved in `profiles.json` as a separate top-level map keyed by profile id. Profile definitions remain focused on account metadata. Persisted connection state contains only non-secret diagnostic data:

- tested host names,
- connected or failed status,
- diagnostic message text,
- ISO-8601 test timestamp.

Older profile stores that do not include connection state continue to load with an empty status map.

## Auto Test Behavior

Manual `Test Connection` keeps its current UI behavior and also writes the latest results to disk.

When the global profile changes, the app starts a background SSH connection test for the new active profile. The automatic test runs only for SSH profiles with at least one configured host and a configured SSH key path. HTTPS profiles do not run SSH tests and continue to present HTTPS credential status.

If the user switches profiles while a test is running, the result is still saved for the profile that was tested. The visible settings message is updated only when it still refers to the selected or active profile.

## Safety

This changes the previous manual-only network policy. The new automatic behavior is limited to user-triggered profile switches and never runs broad account discovery, telemetry, analytics, crash upload, or update checks. Secrets are not stored in JSON.

Existing `~/.gitconfig` and `~/.ssh/config` are not replaced. Shell execution stays behind injected command runners.

## Testing

Tests cover:

- profile stores round-trip persisted connection state,
- older store JSON without connection state remains compatible,
- manual connection tests save state that survives a new view model,
- switching the active profile starts a background test for the switched SSH profile,
- profile switching does not require the tested profile to remain selected before saving its result.
