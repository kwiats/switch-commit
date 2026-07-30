# Manual Host Connection Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add manual host connection testing with red, orange, and green account status indicators in the menu bar settings UI.

**Architecture:** Core owns SSH command construction and result interpretation through `DiagnosticsService` and injected `CommandRunning`. App logic stores runtime-only status results in `AppViewModel`, while SwiftUI/AppKit only render provider icons, status colors, labels, and the `Test Connection` action.

**Tech Stack:** Swift 6.2 package, SwiftUI/AppKit, Combine, local `GitAccountSwitcherCoreTestRunner`.

---

### Task 1: Core Connection Test Result

**Files:**
- Modify: `Sources/GitAccountSwitcherCore/DiagnosticsService.swift`
- Test: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing core tests**

Add tests that instantiate a fake `CommandRunning`, call `DiagnosticsService.testSSHConnection(host:)`, and assert:

```swift
try expect(service.sshConnectionTestCommand(host: "github.com") == ("ssh", ["-o", "BatchMode=yes", "-T", "git@github.com"]), "github command should use git user")
try expect(service.sshConnectionTestCommand(host: "gitlab.com") == ("ssh", ["-o", "BatchMode=yes", "-T", "git@gitlab.com"]), "generic host command should use git user")
try expect(githubResult.status == .connected, "github success text should count as connected")
try expect(failedResult.status == .failed, "non-success result should fail")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: compile failure because `sshConnectionTestCommand`, `testSSHConnection`, and result types do not exist yet.

- [ ] **Step 3: Implement minimal core API**

In `DiagnosticsService.swift`, add:

```swift
public enum HostConnectionTestStatus: Equatable, Sendable {
    case connected
    case failed
}

public struct HostConnectionTestResult: Equatable, Sendable {
    public var host: String
    public var status: HostConnectionTestStatus
    public var message: String
}
```

Add `sshConnectionTestCommand(host:)` and `testSSHConnection(host:)`. Use `ssh -o BatchMode=yes -T git@<host>`. Treat exit code `0` as connected. For `github.com`, also treat output containing `successfully authenticated` as connected.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: PASS.

### Task 2: Runtime Profile Status in App Logic

**Files:**
- Modify: `Sources/GitAccountSwitcherAppLogic/AppViewModel.swift`
- Test: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing app logic tests**

Add tests that create `AppViewModel` with fake profiles and a fake diagnostics service/runner, then assert:

```swift
try expect(viewModel.connectionStatus(for: profile).displayColorName == "red", "untested profile should be red")
viewModel.testConnectionForSelectedProfile()
try expect(viewModel.connectionStatus(for: profile).displayColorName == "green", "successful manual test should be green")
```

Also add an orange assertion for a failed fake SSH result.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: compile failure because `connectionStatus(for:)`, `testConnectionForSelectedProfile`, and injectable diagnostics do not exist yet.

- [ ] **Step 3: Implement runtime status state**

In `AppViewModel.swift`, replace the mock binding-only enum with a connection status enum containing red, orange, and green presentation metadata. Inject `DiagnosticsService` or a small testable host connection service. Store latest results in a dictionary keyed by profile id. Add `testConnectionForSelectedProfile()` that validates hosts and runs tests only when called.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: PASS.

### Task 3: Settings UI and Menu Rendering

**Files:**
- Modify: `Sources/GitAccountSwitcherApp/SettingsView.swift`
- Modify: `Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift`
- Test: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing presentation tests**

Add small tests for provider icon and status presentation metadata:

```swift
try expect(viewModel.providerSystemImageName(for: githubProfile) == "person.crop.circle.badge.checkmark", "github profile should expose provider icon")
try expect(viewModel.connectionStatus(for: githubProfile).systemImageName == "circle.fill", "status should expose dot icon")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: compile failure because provider presentation helpers do not exist.

- [ ] **Step 3: Implement UI rendering**

In `SettingsView`, update sidebar rows to show provider icon and colored status dot. Update the selected profile header to show a larger colored status, status text, and `Test Connection` button. In `GitAccountSwitcherApp`, keep menu item status images in sync with the new connection status metadata.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: PASS.

### Task 4: Verification and Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/release-notes/v0.1.0.md`

- [ ] **Step 1: Update docs**

Document that connection status is manual-only and that no automatic network checks run.

- [ ] **Step 2: Run full verification**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
```

Expected: both commands succeed.

- [ ] **Step 3: Commit and publish**

Run:

```bash
git status --short
git add Sources/GitAccountSwitcherCore/DiagnosticsService.swift Sources/GitAccountSwitcherAppLogic/AppViewModel.swift Sources/GitAccountSwitcherApp/SettingsView.swift Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift README.md docs/release-notes/v0.1.0.md docs/superpowers/specs/2026-07-30-manual-host-connection-status-design.md docs/superpowers/plans/2026-07-30-manual-host-connection-status-implementation.md
git commit -m "feat: add manual host connection status"
git push -u origin codex/manual-host-connection-status
```

Expected: branch is pushed for PR creation.
