# GitPersona Manual Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a manual GitPersona update check path backed by Sparkle while preserving the no automatic network calls safety contract.

**Architecture:** Keep Sparkle isolated in the App target. AppLogic owns update presentation state and calls a small injected update-checking protocol, so tests can verify behavior without importing Sparkle or touching the network. Settings gets a dedicated Updates tab with product/version display, privacy copy, and a user-initiated update button.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, Swift Package Manager, Sparkle 2, existing `GitAccountSwitcherCoreTestRunner`.

---

## File Structure

- Modify `Package.swift`: add Sparkle as an SPM dependency and link it only to `GitAccountSwitcherApp`.
- Modify `Sources/GitAccountSwitcherAppLogic/AppViewModel.swift`: add update presentation data, an injected `AppUpdateChecking` protocol, and `checkForUpdates()` behavior.
- Modify `Sources/GitAccountSwitcherApp/SettingsView.swift`: add an Updates tab and wire its button to the view model.
- Modify `Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift`: construct the view model with a Sparkle-backed update checker.
- Create `Sources/GitAccountSwitcherApp/SparkleAppUpdateChecker.swift`: isolate Sparkle imports, suppress automatic-check permission prompts, and expose manual update invocation.
- Modify `Sources/GitAccountSwitcherCoreTestRunner/main.swift`: add app logic tests for update presentation and manual button behavior.
- Modify `README.md`: document GitPersona, the public release channel, and the manual update network exception.
- Create `docs/release-notes/v0.2.0.md`: document the customer-facing GitPersona update direction.

The implementation intentionally does not add a runtime GitHub token path, GitHub API access, automatic update checks, or release publishing automation.

## Task 1: App Logic Update Presentation

**Files:**
- Modify: `Sources/GitAccountSwitcherAppLogic/AppViewModel.swift`
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing tests for update presentation and manual update checks**

Add these tests near the other `AppViewModel` tests in `Sources/GitAccountSwitcherCoreTestRunner/main.swift`:

```swift
("app view model exposes GitPersona update presentation", {
    final class RecordingUpdateChecker: AppUpdateChecking {
        var canCheckForUpdates = true
        private(set) var checkCount = 0

        func checkForUpdates() {
            checkCount += 1
        }
    }

    let checker = RecordingUpdateChecker()
    let viewModel = AppViewModel(
        profiles: [],
        keychainStore: InMemoryKeychainStore(),
        updateChecker: checker,
        bundleInfo: AppBundleInfo(
            shortVersion: "1.2.3",
            buildVersion: "45"
        )
    )

    try expect(viewModel.updatePresentation.productName == "GitPersona", "updates should use the customer-facing product name")
    try expect(viewModel.updatePresentation.installedVersion == "1.2.3 (45)", "updates should show semantic version and build")
    try expect(viewModel.updatePresentation.canCheckForUpdates, "manual update checks should be enabled when checker allows it")
    try expect(viewModel.updatePresentation.privacyNote == "Checks the public GitPersona release channel only after you click.", "privacy note should explain manual network access")

    viewModel.checkForUpdates()

    try expect(checker.checkCount == 1, "manual update check should call the injected checker once")
    try expect(viewModel.settingsMessage == "Checking GitPersona updates...", "manual check should show a user-initiated status message")
}),
("app view model reports disabled update checker without network access", {
    final class DisabledRecordingUpdateChecker: AppUpdateChecking {
        var canCheckForUpdates = false
        private(set) var checkCount = 0

        func checkForUpdates() {
            checkCount += 1
        }
    }

    let checker = DisabledRecordingUpdateChecker()
    let viewModel = AppViewModel(
        profiles: [],
        keychainStore: InMemoryKeychainStore(),
        updateChecker: checker,
        bundleInfo: AppBundleInfo(
            shortVersion: nil,
            buildVersion: nil
        )
    )

    try expect(viewModel.updatePresentation.installedVersion == "Development Build", "missing bundle version should use a debug-friendly fallback")
    try expect(!viewModel.updatePresentation.canCheckForUpdates, "presentation should reflect disabled checker")

    viewModel.checkForUpdates()

    try expect(checker.checkCount == 0, "disabled checker must not be called")
    try expect(viewModel.settingsMessage == "Updates are not available in this build.", "disabled checker should explain why nothing happened")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: fail to compile because `AppUpdateChecking`, `AppBundleInfo`, `updateChecker`, `bundleInfo`, `updatePresentation`, and `checkForUpdates()` do not exist.

- [ ] **Step 3: Add app update model and injected checker**

Add this code in `Sources/GitAccountSwitcherAppLogic/AppViewModel.swift` after `AppPresentationRequest`:

```swift
public struct AppBundleInfo: Equatable, Sendable {
    public let shortVersion: String?
    public let buildVersion: String?

    public init(shortVersion: String?, buildVersion: String?) {
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
    }

    public static func mainBundle() -> AppBundleInfo {
        let info = Bundle.main.infoDictionary
        return AppBundleInfo(
            shortVersion: info?["CFBundleShortVersionString"] as? String,
            buildVersion: info?["CFBundleVersion"] as? String
        )
    }
}

public struct AppUpdatePresentation: Equatable, Sendable {
    public let productName: String
    public let installedVersion: String
    public let canCheckForUpdates: Bool
    public let privacyNote: String
}

@MainActor
public protocol AppUpdateChecking: AnyObject {
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

@MainActor
public final class DisabledAppUpdateChecker: AppUpdateChecking {
    public init() {}

    public var canCheckForUpdates: Bool {
        false
    }

    public func checkForUpdates() {}
}
```

Add these stored properties to `AppViewModel`:

```swift
private let updateChecker: AppUpdateChecking
private let bundleInfo: AppBundleInfo
```

Update the `AppViewModel` initializer signature:

```swift
public init(
    profiles: [GitProfile]? = nil,
    activeProfileId: String? = nil,
    diagnosticsText: String = "Diagnostics have not run.",
    presentationRequest: AppPresentationRequest? = nil,
    profileStore: ProfileStore? = nil,
    keychainStore: KeychainStoring = SystemKeychainStore(),
    gitConfigInstaller: GitConfigInstalling? = nil,
    githubDiscoveryService: GitHubLocalDiscoveryService? = nil,
    diagnosticsService: DiagnosticsService = DiagnosticsService(),
    updateChecker: AppUpdateChecking = DisabledAppUpdateChecker(),
    bundleInfo: AppBundleInfo = .mainBundle()
)
```

Assign the new properties near the other `self.` assignments:

```swift
self.updateChecker = updateChecker
self.bundleInfo = bundleInfo
```

Add these public APIs inside `AppViewModel`:

```swift
public var updatePresentation: AppUpdatePresentation {
    AppUpdatePresentation(
        productName: "GitPersona",
        installedVersion: formattedInstalledVersion,
        canCheckForUpdates: updateChecker.canCheckForUpdates,
        privacyNote: "Checks the public GitPersona release channel only after you click."
    )
}

public func checkForUpdates() {
    guard updateChecker.canCheckForUpdates else {
        settingsMessage = "Updates are not available in this build."
        return
    }
    settingsMessage = "Checking GitPersona updates..."
    updateChecker.checkForUpdates()
}

private var formattedInstalledVersion: String {
    let shortVersion = bundleInfo.shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
    let buildVersion = bundleInfo.buildVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
    switch (shortVersion?.isEmpty == false ? shortVersion : nil, buildVersion?.isEmpty == false ? buildVersion : nil) {
    case (.some(let shortVersion), .some(let buildVersion)):
        return "\(shortVersion) (\(buildVersion))"
    case (.some(let shortVersion), nil):
        return shortVersion
    case (nil, .some(let buildVersion)):
        return "Build \(buildVersion)"
    case (nil, nil):
        return "Development Build"
    }
}
```

- [ ] **Step 4: Run tests to verify Task 1 passes**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: all tests pass.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add Sources/GitAccountSwitcherAppLogic/AppViewModel.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: add update presentation model"
```

## Task 2: Updates Tab UI

**Files:**
- Modify: `Sources/GitAccountSwitcherApp/SettingsView.swift`

- [ ] **Step 1: Verify the existing app logic test covers the UI action contract**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: all tests pass, including `app view model exposes GitPersona update presentation`, which verifies that clicking the UI button can safely call `viewModel.checkForUpdates()`.

- [ ] **Step 2: Add the Updates tab**

Modify `SettingsTab` in `Sources/GitAccountSwitcherApp/SettingsView.swift`:

```swift
private enum SettingsTab: Hashable {
    case accounts
    case detection
    case updates
}
```

Add this tab inside `TabView` after `detectionTab`:

```swift
updatesTab
    .tabItem {
        Label("Updates", systemImage: "arrow.down.circle")
    }
    .tag(SettingsTab.updates)
```

Add this view to `SettingsView`:

```swift
private var updatesTab: some View {
    let presentation = viewModel.updatePresentation
    return VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.productName)
                .font(.title2)
            Text("Version \(presentation.installedVersion)")
                .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    viewModel.checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .disabled(!presentation.canCheckForUpdates)

                Spacer()
            }

            Text(presentation.privacyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()
        footer
    }
    .padding(20)
}
```

- [ ] **Step 3: Build to verify SwiftUI compiles**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 4: Run tests**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: all tests pass.

- [ ] **Step 5: Commit Task 2**

Run:

```bash
git add Sources/GitAccountSwitcherApp/SettingsView.swift
git commit -m "feat: add updates settings tab"
```

## Task 3: Sparkle Adapter

**Files:**
- Modify: `Package.swift`
- Create: `Sources/GitAccountSwitcherApp/SparkleAppUpdateChecker.swift`
- Modify: `Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift`

- [ ] **Step 1: Add Sparkle dependency**

Modify `Package.swift` to add a package dependency:

```swift
dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
],
```

Modify the `GitAccountSwitcherApp` target dependencies:

```swift
.executableTarget(
    name: "GitAccountSwitcherApp",
    dependencies: [
        "GitAccountSwitcherAppLogic",
        "GitAccountSwitcherCore",
        .product(name: "Sparkle", package: "Sparkle")
    ]
),
```

Keep `GitAccountSwitcherCore` and `GitAccountSwitcherAppLogic` free of Sparkle imports.

- [ ] **Step 2: Create the Sparkle wrapper**

Create `Sources/GitAccountSwitcherApp/SparkleAppUpdateChecker.swift`:

```swift
import Foundation
import GitAccountSwitcherAppLogic
import Sparkle

@MainActor
final class SparkleAppUpdateChecker: NSObject, AppUpdateChecking {
    private let updaterDelegate: ManualSparkleUpdaterDelegate
    private let updaterController: SPUStandardUpdaterController
    private var hasStartedUpdater = false

    override init() {
        let createdUpdaterDelegate = ManualSparkleUpdaterDelegate()
        self.updaterDelegate = createdUpdaterDelegate
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: createdUpdaterDelegate,
            userDriverDelegate: nil
        )
        super.init()
    }

    var canCheckForUpdates: Bool {
        false
    }

    func checkForUpdates() {
        if !hasStartedUpdater {
            updaterController.updater.automaticallyChecksForUpdates = false
            updaterController.updater.automaticallyDownloadsUpdates = false
            updaterController.startUpdater()
            hasStartedUpdater = true
        }
        updaterController.checkForUpdates(nil)
    }
}

private final class ManualSparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }

    func feedParameters(for updater: SPUUpdater, sendingSystemProfile sendingProfile: Bool) -> [[String: String]] {
        []
    }
}
```

- [ ] **Step 3: Inject Sparkle into the app view model**

Modify `Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift`:

```swift
private let updateChecker = SparkleAppUpdateChecker()
private lazy var viewModel = AppViewModel(updateChecker: updateChecker)
```

Because the class currently has a `let viewModel = AppViewModel()`, replace that line with the two lines above. The app delegate is `@MainActor`, so constructing the Sparkle wrapper and view model there is safe.

- [ ] **Step 4: Resolve package dependencies and build**

Run:

```bash
swift build
```

Expected: SwiftPM resolves Sparkle and build succeeds. If SwiftPM cannot fetch dependencies because of sandboxed network restrictions, re-run the same command with escalation.

- [ ] **Step 5: Run tests**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: all tests pass. The test runner should not link Sparkle because only the App executable target depends on Sparkle.

- [ ] **Step 6: Commit Task 3**

Run:

```bash
git add Package.swift Package.resolved Sources/GitAccountSwitcherApp/SparkleAppUpdateChecker.swift Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift
git commit -m "feat: wire manual Sparkle update checks"
```

## Task 4: Sparkle Configuration And Safety Docs

**Files:**
- Modify: `README.md`
- Create: `docs/release-notes/v0.2.0.md`

- [ ] **Step 1: Update README safety contract**

Modify the Safety Contract list in `README.md`:

```markdown
- No automatic network calls.
- Manual update checks contact the public GitPersona release channel only after the user clicks `Check for Updates`.
```

Add this section after the Safety Contract:

```markdown
### Manual Updates

GitPersona uses a public release channel for update metadata and signed app artifacts. The source repository can remain private because the app never downloads updates from the private repository and never embeds GitHub tokens.

The app checks for updates only when the user clicks `Check for Updates` in Settings. Update artifacts must be signed before publication, and Sparkle verifies the downloaded update before installation.
```

- [ ] **Step 2: Add release notes**

Create `docs/release-notes/v0.2.0.md`:

```markdown
# GitPersona v0.2.0

## Planned

- Introduces GitPersona as the customer-facing product name.
- Adds a manual update path backed by a public release channel.
- Keeps source code private while publishing only signed distribution artifacts.
- Preserves the no automatic network calls safety contract by checking for updates only after a user click.
```

- [ ] **Step 3: Run documentation scan**

Run:

```bash
rg -n "No automatic network calls|Manual Updates|GitPersona|token|private repository" README.md docs/release-notes/v0.2.0.md docs/superpowers/specs/2026-07-30-gitpersona-manual-updates-design.md
```

Expected: output shows the explicit manual update exception and does not suggest runtime GitHub token usage.

- [ ] **Step 4: Run build and tests**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
```

Expected: both commands pass.

- [ ] **Step 5: Commit Task 4**

Run:

```bash
git add README.md docs/release-notes/v0.2.0.md
git commit -m "docs: document GitPersona update channel"
```

## Task 5: Final Verification And PR Update

**Files:**
- No new files unless verification reveals an issue.

- [ ] **Step 1: Run full local verification**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
```

Expected: both commands pass.

- [ ] **Step 2: Inspect final diff**

Run:

```bash
git status --short --branch
git log --oneline main..HEAD
git diff --stat main...HEAD
```

Expected: branch contains the spec commit plus implementation commits. Working tree is clean.

- [ ] **Step 3: Push branch**

Run:

```bash
git push
```

Expected: remote branch updates successfully.

- [ ] **Step 4: Update draft PR body**

Run:

```bash
gh pr edit 22 --body "## Summary

- Adds GitPersona update presentation state and Settings UI.
- Wires manual Sparkle update checks through an App-target adapter.
- Documents the public release channel model and manual network-access exception.

## Validation

- swift run GitAccountSwitcherCoreTestRunner
- swift build"
```

Expected: PR body updates successfully.

## Notes For Implementation

Sparkle setup must use manual checks only. Suppress Sparkle's automatic-check permission prompt and do not add a launch-time update call. The app should only call Sparkle from `viewModel.checkForUpdates()`, which is reached from the Settings button.

The appcast URL and public EdDSA key may need final release-channel values before shipping an installable build. If those values are not available during implementation, keep update installation disabled for debug builds by allowing `canCheckForUpdates` to report false until the final bundle configuration exists. Do not add fake runtime URLs that look production-ready.
