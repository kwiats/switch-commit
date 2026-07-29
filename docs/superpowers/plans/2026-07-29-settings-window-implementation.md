# Settings Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a first functional Settings window for managing Git account profiles.

**Architecture:** Move account mutation behavior into an importable core manager so the local test runner can verify it. Keep SwiftUI thin: `AppViewModel` owns the core manager, republishes state, and the Settings scene binds controls to view-model methods.

**Tech Stack:** Swift 6.2, SwiftUI, local executable test runner, existing `GitAccountSwitcherCore` models, `ProfileStore`, and `KeychainStoring`.

---

## File Structure

- Create `Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift`: importable profile/account mutation logic, persistence, keychain reset.
- Modify `Sources/GitAccountSwitcherCore/KeychainStore.swift`: allow deleting a keychain credential from an existing raw credential reference.
- Modify `Sources/GitAccountSwitcherCoreTestRunner/main.swift`: add failing tests for manager behavior first.
- Modify `Sources/GitAccountSwitcherApp/AppViewModel.swift`: wrap the core manager and expose Settings actions to SwiftUI.
- Modify `Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift`: replace placeholder Settings content with a two-column account management view.

### Task 1: Core Manager Tests

**Files:**
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`
- Create later: `Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift`
- Modify later: `Sources/GitAccountSwitcherCore/KeychainStore.swift`

- [ ] **Step 1: Write failing tests**

Add tests to the local runner for:

```swift
("profile settings manager adds a valid profile and selects it", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        seedProfiles: []
    )

    try manager.addProfile()

    try expect(manager.profiles.count == 1, "add should create one profile")
    try expect(manager.activeProfileId == manager.profiles[0].id, "added profile should become active")
    try expect(manager.selectedProfileId == manager.profiles[0].id, "added profile should become selected")
    let loaded = try ProfileStore(fileURL: storeURL).load()
    try expect(loaded.profiles == manager.profiles, "added profile should persist")
}),
("profile settings manager updates active display name", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let profile = try GitProfile(
        id: "personal",
        displayName: "Personal",
        gitUserName: "Personal User",
        gitUserEmail: "me@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        seedProfiles: [profile]
    )

    try manager.updateSelectedProfile(displayName: "Top Name")

    try expect(manager.activeProfile?.displayName == "Top Name", "active profile display name should update")
}),
("profile settings manager keeps selection valid when deleting profiles", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let first = try GitProfile(
        id: "first",
        displayName: "First",
        gitUserName: "First User",
        gitUserEmail: "first@example.com",
        sshKeyPath: "~/.ssh/id_first",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let second = try GitProfile(
        id: "second",
        displayName: "Second",
        gitUserName: "Second User",
        gitUserEmail: "second@example.com",
        sshKeyPath: "~/.ssh/id_second",
        hosts: ["gitlab.com"],
        httpsCredentialRef: nil,
        isDefault: false
    )
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        seedProfiles: [first, second]
    )

    try manager.deleteSelectedProfile()
    try expect(manager.profiles.map(\\.id) == ["second"], "delete should remove selected profile")
    try expect(manager.activeProfileId == "second", "remaining profile should become active")

    try manager.deleteSelectedProfile()
    try expect(manager.profiles.isEmpty, "second delete should remove last profile")
    try expect(manager.activeProfileId == nil, "active profile should clear after deleting last profile")
    try expect(manager.selectedProfileId == nil, "selected profile should clear after deleting last profile")
}),
("profile settings manager resets https access", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let identifier = KeychainCredentialIdentifier(profileId: "work", purpose: "https")
    let profile = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work User",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: identifier.rawValue,
        isDefault: true
    )
    let keychain = InMemoryKeychainStore()
    try keychain.save("secret", for: identifier)
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: keychain,
        seedProfiles: [profile]
    )

    try manager.resetAccessForSelectedProfile()

    try expect(try keychain.read(identifier) == nil, "reset should delete keychain value")
    try expect(manager.profiles[0].httpsCredentialRef == nil, "reset should clear credential reference")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: compile failure because `ProfileSettingsManager` does not exist.

### Task 2: Core Manager Implementation

**Files:**
- Create: `Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift`
- Modify: `Sources/GitAccountSwitcherCore/KeychainStore.swift`

- [ ] **Step 1: Implement raw keychain identifier support**

Add this initializer:

```swift
public init(rawValue: String) {
    self.rawValue = rawValue
}
```

- [ ] **Step 2: Implement `ProfileSettingsManager`**

Create a final class that:

```swift
public final class ProfileSettingsManager {
    public private(set) var profiles: [GitProfile]
    public private(set) var rules: [FolderRule]
    public private(set) var activeProfileId: String?
    public private(set) var selectedProfileId: String?
    public private(set) var statusMessage: String?

    public var activeProfile: GitProfile? { get }
    public var selectedProfile: GitProfile? { get }

    public init(profileStore: ProfileStore, keychainStore: KeychainStoring, seedProfiles: [GitProfile]) throws
    public func selectProfile(id: String?)
    public func switchGlobalProfile(to profile: GitProfile) throws
    public func addProfile() throws
    public func deleteSelectedProfile() throws
    public func updateSelectedProfile(displayName: String) throws
    public func updateSelectedProfile(gitUserName: String) throws
    public func updateSelectedProfile(gitUserEmail: String) throws
    public func updateSelectedProfile(sshKeyPath: String) throws
    public func updateSelectedProfile(hostsText: String) throws
    public func resetAccessForSelectedProfile() throws
}
```

Every mutating method calls `persist()` after successful changes.

- [ ] **Step 3: Run tests to verify pass**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: all tests pass.

- [ ] **Step 4: Commit core manager**

Run:

```bash
git add Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift Sources/GitAccountSwitcherCore/KeychainStore.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: add profile settings manager"
```

### Task 3: App View Model Wiring

**Files:**
- Modify: `Sources/GitAccountSwitcherApp/AppViewModel.swift`

- [ ] **Step 1: Replace direct array ownership with manager-backed state**

`AppViewModel` should initialize a `ProfileSettingsManager`, publish snapshots, and expose:

```swift
var activeProfile: GitProfile? { get }
var selectedProfile: GitProfile? { get }
var hostsTextForSelectedProfile: String { get }
func selectProfile(id: String?)
func addProfile()
func deleteSelectedProfile()
func updateSelectedProfile(displayName: String)
func updateSelectedProfile(gitUserName: String)
func updateSelectedProfile(gitUserEmail: String)
func updateSelectedProfile(sshKeyPath: String)
func updateSelectedProfile(hostsText: String)
func resetAccessForSelectedProfile()
```

Each method catches errors into `settingsMessage`.

- [ ] **Step 2: Build**

Run: `swift build`

Expected: build succeeds.

### Task 4: SwiftUI Settings Window

**Files:**
- Modify: `Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift`

- [ ] **Step 1: Replace placeholder settings content**

Use a two-column `NavigationSplitView` or `HStack`:

```swift
HStack(spacing: 0) {
    accountList
    Divider()
    accountForm
}
.frame(width: 680, height: 420)
```

The list has add/delete icon buttons. The form has text fields for display name, git user name, git email, SSH key path, hosts, and a reset access button.

- [ ] **Step 2: Build**

Run: `swift build`

Expected: build succeeds.

### Task 5: Final Verification

**Files:**
- Verify all touched files

- [ ] **Step 1: Run tests**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: all tests pass.

- [ ] **Step 2: Run build**

Run: `swift build`

Expected: build succeeds.

- [ ] **Step 3: Check git status**

Run: `git status --short`

Expected: only intentional changes are present.

- [ ] **Step 4: Commit app UI**

Run:

```bash
git add Sources/GitAccountSwitcherApp/AppViewModel.swift Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift
git commit -m "feat: add account settings window"
```
