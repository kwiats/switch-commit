# Settings Window - Design

## Goal

Add the first real Settings window for Git Account Switcher. The window lets the user manage Git account profiles without leaving the menu bar app.

This iteration should be intentionally thin but functional:

- show all configured accounts,
- select the active account,
- edit the active account display name used at the top of the menu,
- add a new account with required Git identity fields,
- remove an existing account,
- reset locally stored access for an account by clearing its HTTPS credential reference and deleting its matching keychain credential.

## Scope

The existing app has an in-memory `AppViewModel`, a `GitProfile` model, JSON profile storage, and keychain abstractions. This change keeps the first Settings pass inside SwiftUI and `AppViewModel`, while using existing core models and keychain interfaces.

Settings actions should mutate the same profile state used by the menu, so the menu title and active profile details update immediately. Profile mutations in this pass should also persist through `ProfileStoreData` JSON so add, delete, reset, and display-name edits survive app restart.

Full startup wiring can remain small, but the app must have one consistent source of initial profile data: load profiles from `ProfileStore` when available, and fall back to preview/default seed data only when no profile file exists.

## User Experience

The Settings scene becomes a real management surface:

- left side: account list with add and delete controls,
- right side: form for the selected account,
- top area: selected account display name and Git email,
- reset access action near credential-related fields,
- diagnostics text remains visible but secondary.

Deleting the currently active account selects another available account. Deleting the last account leaves the app in an empty state with a clear prompt to add an account.

Adding an account creates a valid default profile draft with a unique id and editable fields. It becomes selected immediately.

## Data Flow

`AppViewModel` owns:

- `profiles`,
- `activeProfileId`,
- selected settings profile id,
- editable operations for profile fields.

Settings views call view-model methods instead of directly editing array internals. The view model validates profile updates by rebuilding `GitProfile` through its throwing initializer.

Reset access uses a `KeychainStoring` dependency. HTTPS credentials must use the existing convention `KeychainCredentialIdentifier(profileId: profile.id, purpose: "https")`, and `httpsCredentialRef` should store that identifier's `rawValue`.

When resetting access, the view model deletes the credential represented by the stored reference, then clears `httpsCredentialRef`. If the stored reference is missing or does not match the current convention, the reset still clears the reference and reports that no matching local credential was found.

## Error Handling

Validation errors are shown as concise messages in Settings and do not crash the app. Delete and reset failures surface in the same message area.

The first pass does not need modal confirmation for delete. It should prevent accidental broken state by keeping profile selection valid after every mutation.

## Testing

Add local test-runner coverage for view-model behavior:

- adding a profile creates a valid profile and selects it,
- editing the display name updates the active menu-facing profile,
- deleting the active profile selects a remaining profile,
- deleting the last profile clears active selection,
- resetting access deletes the in-memory keychain value and clears the credential reference.

Because the current repository uses a local Swift test runner rather than XCTest, the behavior under test must live in a target the runner can import. Move account-management behavior into a core-level service or model helper, or create a small library target for shared app state. Keep SwiftUI view code thin and test the mutations through that importable logic.
