# Settings Detection Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move account detection into its own Settings tab and show provider/source metadata for detected accounts.

**Architecture:** Keep detection state and actions in `AppViewModel`. Refactor `SettingsView` so account editing and account detection are separate SwiftUI tab views, with source/provider formatting handled by private view helpers.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, existing local test runner.

---

### Task 1: Settings Tab Layout

**Files:**
- Modify: `Sources/GitAccountSwitcherApp/SettingsView.swift`

- [ ] **Step 1: Introduce a settings tab selection state**

Add a private enum and `@State` in `SettingsView`:

```swift
private enum SettingsTab: Hashable {
    case accounts
    case detection
}

@State private var selectedTab: SettingsTab = .accounts
```

- [ ] **Step 2: Replace the root body content with `TabView`**

Wrap the existing account management layout in an `Accounts` tab and add a `Detection` tab:

```swift
TabView(selection: $selectedTab) {
    accountsTab
        .tabItem { Label("Accounts", systemImage: "person.2") }
        .tag(SettingsTab.accounts)

    detectionTab
        .tabItem { Label("Detection", systemImage: "magnifyingglass") }
        .tag(SettingsTab.detection)
}
```

- [ ] **Step 3: Remove detection from account details**

Delete `detectedAccountsSection` from the selected-profile and empty account detail layouts so the account form has stable space.

### Task 2: Detection Results UI

**Files:**
- Modify: `Sources/GitAccountSwitcherApp/SettingsView.swift`

- [ ] **Step 1: Expand detection controls**

Create a dedicated detection tab with a title, local-only note, detect button, folder scan button, and the existing results section.

- [ ] **Step 2: Show provider and source labels**

Add helper functions for provider and source display text:

```swift
private func providerLabel(_ provider: GitAccountProvider) -> String
private func detectionSourceLabel(_ source: DetectionSource) -> String
private func detectionSourcesText(_ sources: [DetectionSource]) -> String
```

- [ ] **Step 3: Make result rows readable**

Render each detected account in a full-width result row with:

- username or fallback title;
- email or warning subtitle;
- provider label;
- sources text;
- confidence;
- `Add` or `Complete` action.

### Task 3: Verify and Publish

**Files:**
- Test: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Run local test runner**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: all test runner checks pass.

- [ ] **Step 2: Run build**

Run:

```bash
swift build
```

Expected: build completes successfully.

- [ ] **Step 3: Commit, push, and open draft PR**

Run:

```bash
git add docs/superpowers/specs/2026-07-30-settings-detection-tab-design.md docs/superpowers/plans/2026-07-30-settings-detection-tab-implementation.md Sources/GitAccountSwitcherApp/SettingsView.swift
git commit -m "Improve account detection settings layout"
git push -u origin codex/settings-detection-tab
```

Open a draft pull request for `codex/settings-detection-tab`.
