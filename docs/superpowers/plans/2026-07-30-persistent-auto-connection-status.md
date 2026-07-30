# Persistent Auto Connection Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist latest connection test results per profile and refresh the active SSH profile automatically after profile switches.

**Architecture:** Core adds Codable persistent connection-state models and stores them as a separate top-level field in `ProfileStoreData`. `AppViewModel` initializes from persisted state, saves new manual and automatic test results through `ProfileSettingsManager`, and starts automatic SSH tests after successful global profile switches.

**Tech Stack:** Swift 6.2 package, Foundation JSONEncoder/JSONDecoder, existing local `GitAccountSwitcherCoreTestRunner`.

---

### Task 1: Persistent Store Models

**Files:**
- Modify: `Sources/GitAccountSwitcherCore/Models.swift`
- Modify: `Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift`
- Test: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing tests**

Add tests that create a `PersistedProfileConnectionState`, save it through `ProfileStoreData`, reload it, and assert the profile id, host result, status, message, and timestamp survive. Add a compatibility test that decodes legacy JSON with only `profiles` and `rules` and expects an empty `profileConnectionStates` map.

- [ ] **Step 2: Run red test**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: FAIL because persistent connection state types and `ProfileStoreData.profileConnectionStates` do not exist.

- [ ] **Step 3: Implement minimal models**

Add `PersistedHostConnectionTestResult` and `PersistedProfileConnectionState` as Codable, Equatable, Sendable structs. Add `profileConnectionStates: [String: PersistedProfileConnectionState]` to `ProfileStoreData` with decode defaulting to `[:]`.

- [ ] **Step 4: Pass focused tests**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: PASS.

### Task 2: View Model Persistence And Auto Refresh

**Files:**
- Modify: `Sources/GitAccountSwitcherAppLogic/AppViewModel.swift`
- Modify: `Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift`
- Test: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing tests**

Add tests that manual `testConnectionForSelectedProfile()` writes persisted state and that a new `AppViewModel` using the same store starts green. Add a test that `switchGlobalProfile(to:)` starts an automatic background test for the switched SSH profile and saves the result even when selected profile differs.

- [ ] **Step 2: Run red test**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: FAIL because app logic does not load, save, or auto-run persistent connection tests.

- [ ] **Step 3: Implement minimal persistence hooks**

Expose connection state through `ProfileSettingsManager`, add a save method for one profile's connection results, initialize `AppViewModel.connectionTestResultsByProfileId` from stored results, and save after manual/automatic tests complete.

- [ ] **Step 4: Implement automatic switched-profile test**

After successful `switchGlobalProfile(to:)`, start a background connection test for the switched profile when it is an SSH profile with hosts and SSH key path. Persist results by profile id regardless of current selection.

- [ ] **Step 5: Pass focused tests**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: PASS.

### Task 3: Documentation And Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/release-notes/v0.2.0.md`
- Modify: `docs/superpowers/specs/2026-07-30-manual-host-connection-status-design.md`

- [ ] **Step 1: Update docs**

Replace manual-only language with user-triggered profile-switch auto refresh language. State that persisted connection status contains no secrets.

- [ ] **Step 2: Run full verification**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: PASS.

Run: `swift build`

Expected: PASS.

- [ ] **Step 3: Commit and publish**

Commit the completed changes with message `feat: persist connection status per profile`, push the branch, and open a draft PR.
