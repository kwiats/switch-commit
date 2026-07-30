# Launch at Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit Settings toggle that lets the user start Git Account Switcher automatically at macOS login.

**Architecture:** Add a testable `LaunchAtLoginManaging` protocol in app logic, inject it into `AppViewModel`, and implement the real adapter with `ServiceManagement.SMAppService.mainApp` in the app target. Show the setting in a small General tab in `SettingsView`.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, ServiceManagement, local `GitAccountSwitcherCoreTestRunner`.

---

### Task 1: App Logic State

**Files:**
- Modify: `Sources/GitAccountSwitcherAppLogic/AppViewModel.swift`
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing tests**

Add tests for initial state, successful enable, successful disable, and failed enable using a fake launch-at-login manager.

- [ ] **Step 2: Verify red**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: compile failure because `LaunchAtLoginManaging` and launch-at-login view-model APIs do not exist yet.

- [ ] **Step 3: Implement minimal app-logic API**

Add `LaunchAtLoginManaging`, `LaunchAtLoginStatus`, `UnavailableLaunchAtLoginManager`, and view-model methods/properties.

- [ ] **Step 4: Verify green**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: all tests pass.

### Task 2: macOS Adapter and Settings UI

**Files:**
- Create: `Sources/GitAccountSwitcherApp/SystemLaunchAtLoginManager.swift`
- Modify: `Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift`
- Modify: `Sources/GitAccountSwitcherApp/SettingsView.swift`
- Modify: `README.md`
- Modify: `docs/release-notes/v0.1.0.md`

- [ ] **Step 1: Add ServiceManagement adapter**

Implement `SystemLaunchAtLoginManager` with `SMAppService.mainApp.status`, `register()`, and `unregister()`.

- [ ] **Step 2: Inject adapter**

Initialize `AppViewModel(launchAtLoginManager: SystemLaunchAtLoginManager())` from the app delegate.

- [ ] **Step 3: Add Settings tab**

Add a `General` tab containing the `Launch at Login` toggle bound to the view model.

- [ ] **Step 4: Update docs**

Mention that autostart is opt-in and managed through macOS Login Items.

- [ ] **Step 5: Verify**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
```

Expected: tests and build pass.
