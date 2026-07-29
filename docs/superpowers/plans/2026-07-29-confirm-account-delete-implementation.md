# Confirm Account Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second-click confirmation before deleting an account from Settings.

**Architecture:** Keep destructive profile deletion in the existing view model. Add testable confirmation copy in app logic, and let `SettingsView` hold the transient alert visibility state.

**Tech Stack:** Swift 6.2, SwiftUI, existing `GitAccountSwitcherCoreTestRunner`.

---

### Task 1: Test Confirmation Copy

**Files:**
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`
- Create later: `Sources/GitAccountSwitcherAppLogic/DeleteAccountConfirmationContent.swift`

- [ ] **Step 1: Write the failing test**

Add a test that references `DeleteAccountConfirmationContent` and checks the exact warning.

```swift
("delete account confirmation warns that removal is irreversible", {
    try expect(
        DeleteAccountConfirmationContent.title == "Delete Account?",
        "delete confirmation should have a clear title"
    )
    try expect(
        DeleteAccountConfirmationContent.confirmButtonTitle == "Delete Account",
        "delete confirmation should name the destructive action"
    )
    try expect(
        DeleteAccountConfirmationContent.message.contains("cannot be restored"),
        "delete confirmation should explain the account cannot be restored"
    )
    try expect(
        DeleteAccountConfirmationContent.message.contains("configure it manually again"),
        "delete confirmation should explain manual reconfiguration is required"
    )
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: compile failure because `DeleteAccountConfirmationContent` does not exist.

### Task 2: Implement Confirmation Copy

**Files:**
- Create: `Sources/GitAccountSwitcherAppLogic/DeleteAccountConfirmationContent.swift`
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Add the app-logic content type**

```swift
public enum DeleteAccountConfirmationContent {
    public static let title = "Delete Account?"
    public static let message = "This account cannot be restored after deletion. To use it again, you will need to configure it manually again in the app."
    public static let confirmButtonTitle = "Delete Account"
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: all tests pass.

### Task 3: Wire SwiftUI Alert

**Files:**
- Modify: `Sources/GitAccountSwitcherApp/SettingsView.swift`

- [ ] **Step 1: Add alert state**

Add `@State private var isShowingDeleteConfirmation = false` to `SettingsView`.

- [ ] **Step 2: Open the alert from the trash button**

Change the trash button action to set `isShowingDeleteConfirmation = true`.

- [ ] **Step 3: Add the confirmation alert**

Attach `.alert(DeleteAccountConfirmationContent.title, isPresented: $isShowingDeleteConfirmation)` to the main view. The destructive button calls `viewModel.deleteSelectedProfile()`. The cancel button uses role `.cancel`. The message uses `DeleteAccountConfirmationContent.message`.

- [ ] **Step 4: Verify**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
```

Expected: both commands exit 0.
