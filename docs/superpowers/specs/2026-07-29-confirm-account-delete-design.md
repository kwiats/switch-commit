# Confirm Account Delete - Design

## Goal

Prevent accidental account deletion in Settings by requiring a second, explicit confirmation click before the selected account is removed.

## User Experience

When the user clicks the trash button for the selected account, the app shows a confirmation alert instead of deleting immediately. The alert explains that the account cannot be restored after deletion and that the user must configure it manually again in the app if they want it back.

The alert has two choices:

- `Delete Account`: destructive action that deletes the selected account.
- `Cancel`: default safe action that closes the alert without changing profiles.

The trash button stays disabled when no account is selected.

## Architecture

The deletion behavior remains in `AppViewModel` and `ProfileSettingsManager`. `SettingsView` owns the transient alert state because the confirmation is presentation-only state.

`GitAccountSwitcherAppLogic` exposes small, testable copy for the confirmation alert so the warning text is covered by the existing local test runner and can be reused by SwiftUI without duplicating strings.

## Data Flow

1. User selects an account.
2. User clicks the trash button.
3. `SettingsView` opens the confirmation alert.
4. User clicks `Cancel`, and no model mutation happens.
5. User clicks `Delete Account`, and `SettingsView` calls `viewModel.deleteSelectedProfile()`.

## Error Handling

Deletion failures continue to use the existing `settingsMessage` path in `AppViewModel`. Canceling the alert does not write any files and does not change `settingsMessage`.

## Testing

The core test runner verifies the alert title, destructive button label, and irreversible warning message. `swift build` verifies the SwiftUI alert integration compiles.
