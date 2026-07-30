# Launch at Login Design

## Goal

Add optional macOS login-item registration so Git Account Switcher can start automatically after the user logs in. The setting must be explicit, user-controlled, and off unless the system already reports it as enabled.

## Approach

Use Apple's `ServiceManagement` API through `SMAppService.mainApp` in the app target. Keep direct system calls out of `AppViewModel` by introducing a small app-logic protocol that exposes the current launch-at-login state and can register or unregister the main app.

`AppViewModel` owns the presentation state:

- `isLaunchAtLoginEnabled`: current status shown by Settings,
- `launchAtLoginStatusText`: concise feedback after registration changes,
- `setLaunchAtLoginEnabled(_:)`: updates the system setting and refreshes state.

The real ServiceManagement adapter lives in `GitAccountSwitcherApp`, while tests use an in-memory adapter in `GitAccountSwitcherAppLogic`.

## UI

Settings gets a third `General` tab with a single `Toggle` labeled `Launch at Login`. The tab is intentionally small because autostart is an app preference, not an account preference.

## Error Handling

If registering or unregistering fails, the view model reverts the visible toggle to the adapter's current state and shows an error message. It does not assume the requested state was applied.

## Safety

The feature does not read or write profile secrets, Git config, SSH config, or managed app files. It uses only macOS login-item registration and performs no network work.

## Testing

The core test runner verifies:

- the view model initializes the launch-at-login toggle from the adapter,
- enabling calls registration and updates state,
- disabling calls unregistration and updates state,
- failures refresh the state from the adapter and surface a message.
