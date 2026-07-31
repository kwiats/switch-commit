# Folder Accounts + Live Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users assign folders to accounts in Settings, keep Git switching via managed `includeIf`, and show a live frontmost-folder context preview in the menu bar.

**Architecture:** Pure matching and rule CRUD live in `SwitchCommitCore`. `AppViewModel` exposes folder rows and `FolderContextPresentation`. The app target owns `FrontmostContextMonitor` + path providers (Finder / Terminal / iTerm / Cursor / VS Code), polls every ~2s, and pushes path updates into the view model without changing `activeProfileId`.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, AppleScript / local process inspection for CWD, `SwitchCommitCoreTestRunner` (no XCTest).

**Spec:** `docs/superpowers/specs/2026-07-31-folder-accounts-live-context-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| Create `Sources/SwitchCommitCore/FolderPathNormalizer.swift` | Normalize paths for compare (`~`, absolute, trailing `/`) |
| Create `Sources/SwitchCommitCore/FolderRuleResolver.swift` | Path + rules + active profile → match or global |
| Modify `Sources/SwitchCommitCore/Models.swift` | Add `FolderRuleError` if needed for path conflicts |
| Modify `Sources/SwitchCommitCore/ProfileSettingsManager.swift` | Rule list/add/remove/move + apply installer |
| Create `Sources/SwitchCommitAppLogic/FolderContextPresentation.swift` | Presentation models + `FrontmostPathProviding` protocol |
| Modify `Sources/SwitchCommitAppLogic/AppViewModel.swift` | Folder CRUD APIs, context presentation, menu revision |
| Modify `Sources/SwitchCommitApp/SettingsView.swift` | Folders section under account form |
| Create `Sources/SwitchCommitApp/FrontmostContextMonitor.swift` | 2s poll + push into view model |
| Create `Sources/SwitchCommitApp/FrontmostPathProviders.swift` | Finder / Terminal / iTerm / Cursor / VS Code adapters |
| Modify `Sources/SwitchCommitApp/SwitchCommitApp.swift` | Start monitor; menu header + status title from context |
| Modify `Sources/SwitchCommitCoreTestRunner/main.swift` | Resolver, CRUD, view-model context tests |
| Modify `README.md` | Folder assignments + Automation note |
| Modify `docs/future-features.md` | Section 4 status |
| Modify `docs/release-notes/` (latest / next note) | Mention feature if a notes file exists for the next release |

Do **not** edit legacy `Sources/GitAccountSwitcher*` trees; package targets are `SwitchCommit*`.

---

### Task 1: Path normalizer + folder rule resolver

**Files:**
- Create: `Sources/SwitchCommitCore/FolderPathNormalizer.swift`
- Create: `Sources/SwitchCommitCore/FolderRuleResolver.swift`
- Modify: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing tests**

Append to `tests` in `Sources/SwitchCommitCoreTestRunner/main.swift`:

```swift
("folder path normalizer expands home and strips trailing slash", {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let normalized = FolderPathNormalizer.normalize("~/Work/")
    try expect(normalized == "\(home)/Work", "home and trailing slash should normalize")
}),
("folder rule resolver matches folder tree children", {
    let work = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let rule = try FolderRule(
        id: "work-tree",
        path: "/Users/me/Work",
        profileId: "work",
        matchMode: .folderTree,
        enabled: true
    )
    let resolved = FolderRuleResolver.resolve(
        path: "/Users/me/Work/acme",
        rules: [rule],
        profiles: [work],
        activeProfileId: "work"
    )
    try expect(resolved.kind == .folderRule, "child path should match tree rule")
    try expect(resolved.rule?.id == "work-tree", "matched rule id")
    try expect(resolved.profile?.id == "work", "matched profile")
}),
("folder rule resolver prefers longer prefix on overlap", {
    let personal = try GitProfile(
        id: "personal",
        displayName: "Personal",
        gitUserName: "Me",
        gitUserEmail: "me@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let work = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: false
    )
    let broad = try FolderRule(
        id: "dev",
        path: "/Users/me/Dev",
        profileId: "personal",
        matchMode: .folderTree,
        enabled: true
    )
    let nested = try FolderRule(
        id: "dev-acme",
        path: "/Users/me/Dev/acme",
        profileId: "work",
        matchMode: .folderTree,
        enabled: true
    )
    let resolved = FolderRuleResolver.resolve(
        path: "/Users/me/Dev/acme/src",
        rules: [broad, nested],
        profiles: [personal, work],
        activeProfileId: "personal"
    )
    try expect(resolved.rule?.id == "dev-acme", "longer prefix must win")
}),
("folder rule resolver ignores disabled rules and falls back to global", {
    let personal = try GitProfile(
        id: "personal",
        displayName: "Personal",
        gitUserName: "Me",
        gitUserEmail: "me@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let rule = try FolderRule(
        id: "disabled",
        path: "/Users/me/Work",
        profileId: "personal",
        matchMode: .folderTree,
        enabled: false
    )
    let resolved = FolderRuleResolver.resolve(
        path: "/Users/me/Work",
        rules: [rule],
        profiles: [personal],
        activeProfileId: "personal"
    )
    try expect(resolved.kind == .global, "disabled rule must not match")
    try expect(resolved.profile?.id == "personal", "global active profile")
}),
("folder rule resolver single repo does not match children", {
    let work = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let rule = try FolderRule(
        id: "single",
        path: "/Users/me/Work/repo",
        profileId: "work",
        matchMode: .singleRepo,
        enabled: true
    )
    let child = FolderRuleResolver.resolve(
        path: "/Users/me/Work/repo/subdir",
        rules: [rule],
        profiles: [work],
        activeProfileId: "work"
    )
    try expect(child.kind == .global, "singleRepo should not match nested paths")
    let exact = FolderRuleResolver.resolve(
        path: "/Users/me/Work/repo",
        rules: [rule],
        profiles: [work],
        activeProfileId: "work"
    )
    try expect(exact.kind == .folderRule, "singleRepo should match exact path")
}),
```

- [ ] **Step 2: Verify red**

Run:

```bash
swift run SwitchCommitCoreTestRunner
```

Expected: compile failure — `FolderPathNormalizer` / `FolderRuleResolver` missing.

- [ ] **Step 3: Implement normalizer + resolver**

`Sources/SwitchCommitCore/FolderPathNormalizer.swift`:

```swift
import Foundation

public enum FolderPathNormalizer {
    public static func normalize(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded: String
        if trimmed == "~" {
            expanded = FileManager.default.homeDirectoryForCurrentUser.path
        } else if trimmed.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            expanded = home + String(trimmed.dropFirst(1))
        } else {
            expanded = trimmed
        }
        if expanded.count > 1, expanded.hasSuffix("/") {
            return String(expanded.dropLast())
        }
        return expanded
    }
}
```

`Sources/SwitchCommitCore/FolderRuleResolver.swift`:

```swift
import Foundation

public struct FolderRuleResolution: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case folderRule
        case global
    }

    public var kind: Kind
    public var rule: FolderRule?
    public var profile: GitProfile?

    public init(kind: Kind, rule: FolderRule?, profile: GitProfile?) {
        self.kind = kind
        self.rule = rule
        self.profile = profile
    }
}

public enum FolderRuleResolver {
    public static func resolve(
        path: String,
        rules: [FolderRule],
        profiles: [GitProfile],
        activeProfileId: String?
    ) -> FolderRuleResolution {
        let normalizedPath = FolderPathNormalizer.normalize(path)
        let candidates = rules.filter(\.enabled).compactMap { rule -> (FolderRule, Int)? in
            let rulePath = FolderPathNormalizer.normalize(rule.path)
            guard matches(path: normalizedPath, rulePath: rulePath, mode: rule.matchMode) else {
                return nil
            }
            return (rule, rulePath.count)
        }
        if let best = candidates.max(by: { $0.1 < $1.1 }) {
            let profile = profiles.first { $0.id == best.0.profileId }
            return FolderRuleResolution(kind: .folderRule, rule: best.0, profile: profile)
        }
        let active = profiles.first { $0.id == activeProfileId }
        return FolderRuleResolution(kind: .global, rule: nil, profile: active)
    }

    private static func matches(path: String, rulePath: String, mode: FolderRuleMatchMode) -> Bool {
        switch mode {
        case .singleRepo:
            return path == rulePath
        case .folderTree:
            return path == rulePath || path.hasPrefix(rulePath + "/")
        }
    }
}
```

- [ ] **Step 4: Verify green**

```bash
swift run SwitchCommitCoreTestRunner
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitchCommitCore/FolderPathNormalizer.swift \
  Sources/SwitchCommitCore/FolderRuleResolver.swift \
  Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "$(cat <<'EOF'
feat: resolve folder rules to profiles by path

Add path normalization and pure matching so overlapping folder trees pick the most specific enabled rule.
EOF
)"
```

---

### Task 2: ProfileSettingsManager folder rule CRUD

**Files:**
- Modify: `Sources/SwitchCommitCore/Models.swift` (add `FolderRuleError`)
- Modify: `Sources/SwitchCommitCore/ProfileSettingsManager.swift`
- Modify: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing tests**

```swift
("profile settings manager lists rules only for requested profile", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let work = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let personal = try GitProfile(
        id: "personal",
        displayName: "Personal",
        gitUserName: "Me",
        gitUserEmail: "me@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: false
    )
    try ProfileStore(fileURL: storeURL).save(ProfileStoreData(
        profiles: [work, personal],
        rules: [
            try FolderRule(id: "w1", path: "/Users/me/Work", profileId: "work", matchMode: .folderTree, enabled: true),
            try FolderRule(id: "p1", path: "/Users/me/Personal", profileId: "personal", matchMode: .folderTree, enabled: true)
        ]
    ))
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        seedProfiles: []
    )
    let workRules = manager.rules(forProfileId: "work")
    try expect(workRules.map(\.id) == ["w1"], "only work rules")
}),
("profile settings manager adds folder rule and persists", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let work = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        seedProfiles: [work]
    )
    try manager.addFolderRule(
        path: "/Users/me/Work",
        profileId: "work",
        matchMode: .folderTree,
        forceMove: false
    )
    try expect(manager.rules(forProfileId: "work").count == 1, "rule added")
    let loaded = try ProfileStore(fileURL: storeURL).load()
    try expect(loaded.rules.count == 1, "rule persisted")
}),
("profile settings manager rejects conflicting path without forceMove", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let work = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let personal = try GitProfile(
        id: "personal",
        displayName: "Personal",
        gitUserName: "Me",
        gitUserEmail: "me@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: false
    )
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        seedProfiles: [work, personal]
    )
    try manager.addFolderRule(path: "/Users/me/Shared", profileId: "work", matchMode: .folderTree, forceMove: false)
    try expectThrows(FolderRuleError.pathOwnedByOtherProfile(profileId: "work"), {
        try manager.addFolderRule(path: "/Users/me/Shared", profileId: "personal", matchMode: .folderTree, forceMove: false)
    }, "conflict without forceMove")
}),
("profile settings manager moves conflicting path with forceMove", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let work = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let personal = try GitProfile(
        id: "personal",
        displayName: "Personal",
        gitUserName: "Me",
        gitUserEmail: "me@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: false
    )
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        seedProfiles: [work, personal]
    )
    try manager.addFolderRule(path: "/Users/me/Shared", profileId: "work", matchMode: .folderTree, forceMove: false)
    try manager.addFolderRule(path: "/Users/me/Shared", profileId: "personal", matchMode: .singleRepo, forceMove: true)
    let personalRules = manager.rules(forProfileId: "personal")
    try expect(personalRules.count == 1, "moved to personal")
    try expect(personalRules[0].matchMode == .singleRepo, "mode updated on move")
    try expect(manager.rules(forProfileId: "work").isEmpty, "removed from work")
}),
("profile settings manager removes folder rule", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let work = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        seedProfiles: [work]
    )
    try manager.addFolderRule(path: "/Users/me/Work", profileId: "work", matchMode: .folderTree, forceMove: false)
    let ruleId = try expectValue(manager.rules(forProfileId: "work").first?.id, "rule id")
    try manager.removeFolderRule(id: ruleId)
    try expect(manager.rules(forProfileId: "work").isEmpty, "rule removed")
}),
```

Also add a fake installer test that `addFolderRule` calls `apply` with the new rules (reuse the existing fake installer pattern around line ~1104 in `main.swift`).

- [ ] **Step 2: Verify red**

```bash
swift run SwitchCommitCoreTestRunner
```

Expected: compile failure — missing `FolderRuleError` / CRUD methods.

- [ ] **Step 3: Implement error + CRUD**

In `Models.swift`, extend `SwitchCommitError` or add:

```swift
public enum FolderRuleError: Error, Equatable, Sendable {
    case unknownProfile
    case pathOwnedByOtherProfile(profileId: String)
    case ruleNotFound
}
```

In `ProfileSettingsManager.swift` add:

```swift
public func rules(forProfileId profileId: String) -> [FolderRule] {
    rules
        .filter { $0.profileId == profileId }
        .sorted { FolderPathNormalizer.normalize($0.path) < FolderPathNormalizer.normalize($1.path) }
}

public func addFolderRule(
    path: String,
    profileId: String,
    matchMode: FolderRuleMatchMode,
    forceMove: Bool
) throws {
    guard profiles.contains(where: { $0.id == profileId }) else {
        throw FolderRuleError.unknownProfile
    }
    let normalized = FolderPathNormalizer.normalize(path)
    if let existingIndex = rules.firstIndex(where: {
        FolderPathNormalizer.normalize($0.path) == normalized
    }) {
        let existing = rules[existingIndex]
        if existing.profileId == profileId {
            rules[existingIndex] = try FolderRule(
                id: existing.id,
                path: normalized,
                profileId: profileId,
                matchMode: matchMode,
                enabled: existing.enabled
            )
            try persist()
            try applyGitConfig()
            return
        }
        guard forceMove else {
            throw FolderRuleError.pathOwnedByOtherProfile(profileId: existing.profileId)
        }
        rules[existingIndex] = try FolderRule(
            id: existing.id,
            path: normalized,
            profileId: profileId,
            matchMode: matchMode,
            enabled: true
        )
        try persist()
        try applyGitConfig()
        return
    }

    let rule = try FolderRule(
        id: uniqueRuleId(base: "rule-\(profileId)"),
        path: normalized,
        profileId: profileId,
        matchMode: matchMode,
        enabled: true
    )
    rules.append(rule)
    try persist()
    try applyGitConfig()
}

public func removeFolderRule(id: String) throws {
    guard rules.contains(where: { $0.id == id }) else {
        throw FolderRuleError.ruleNotFound
    }
    rules.removeAll { $0.id == id }
    try persist()
    try applyGitConfig()
}

private func uniqueRuleId(base: String) -> String {
    var candidate = base
    var suffix = 2
    let ids = Set(rules.map(\.id))
    while ids.contains(candidate) {
        candidate = "\(base)-\(suffix)"
        suffix += 1
    }
    return candidate
}
```

Keep existing `deleteSelectedProfile` behavior that removes rules for the deleted profile.

- [ ] **Step 4: Verify green**

```bash
swift run SwitchCommitCoreTestRunner
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitchCommitCore/Models.swift \
  Sources/SwitchCommitCore/ProfileSettingsManager.swift \
  Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "$(cat <<'EOF'
feat: add folder rule CRUD to profile settings

Persist per-profile folder assignments, move conflicts with forceMove, and reapply managed includeIf config.
EOF
)"
```

---

### Task 3: AppViewModel folder + context presentation

**Files:**
- Create: `Sources/SwitchCommitAppLogic/FolderContextPresentation.swift`
- Modify: `Sources/SwitchCommitAppLogic/AppViewModel.swift`
- Modify: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing tests**

```swift
("view model lists folder rules for selected profile only", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let work = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let personal = try GitProfile(
        id: "personal",
        displayName: "Personal",
        gitUserName: "Me",
        gitUserEmail: "me@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: false
    )
    try ProfileStore(fileURL: storeURL).save(ProfileStoreData(
        profiles: [work, personal],
        rules: [
            try FolderRule(id: "w1", path: "/Users/me/Work", profileId: "work", matchMode: .folderTree, enabled: true),
            try FolderRule(id: "p1", path: "/Users/me/Personal", profileId: "personal", matchMode: .folderTree, enabled: true)
        ]
    ))
    let viewModel = AppViewModel(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        gitConfigInstaller: nil
    )
    viewModel.selectProfile(id: "work")
    try expect(viewModel.folderAssignmentsForSelectedProfile.map(\.id) == ["w1"], "only selected profile folders")
}),
("view model add folder rule updates rows and bumps menu revision", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let work = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [work], rules: []))
    let viewModel = AppViewModel(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        gitConfigInstaller: nil
    )
    let before = viewModel.menuContentRevision
    viewModel.setPendingFolderMatchMode(.folderTree)
    viewModel.addFolderRuleForSelectedProfile(path: "/Users/me/Work", forceMove: false)
    try expect(viewModel.folderAssignmentsForSelectedProfile.count == 1, "row added")
    try expect(viewModel.menuContentRevision == before + 1, "menu revision bumped")
}),
("view model apply frontmost path shows folder context without changing active profile", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let personal = try GitProfile(
        id: "personal",
        displayName: "Personal",
        gitUserName: "Me",
        gitUserEmail: "me@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let work = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: false
    )
    try ProfileStore(fileURL: storeURL).save(ProfileStoreData(
        profiles: [personal, work],
        rules: [
            try FolderRule(id: "w1", path: "/Users/me/Work", profileId: "work", matchMode: .folderTree, enabled: true)
        ]
    ))
    let viewModel = AppViewModel(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        gitConfigInstaller: nil
    )
    viewModel.applyFrontmostPath("/Users/me/Work", source: .terminal)
    try expect(viewModel.activeProfileId == "personal", "global active must stay personal")
    if case let .folder(_, profileDisplayName) = viewModel.contextPresentation.kind {
        try expect(profileDisplayName == "Work", "context shows work profile")
    } else {
        throw TestFailure.expectationFailed("expected folder context")
    }
}),
("view model apply unavailable context keeps degraded header", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let personal = try GitProfile(
        id: "personal",
        displayName: "Personal",
        gitUserName: "Me",
        gitUserEmail: "me@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [personal], rules: []))
    let viewModel = AppViewModel(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        gitConfigInstaller: nil
    )
    viewModel.applyFrontmostUnavailable(reason: "Automation denied")
    if case let .unavailable(reason) = viewModel.contextPresentation.kind {
        try expect(reason == "Automation denied", "unavailable reason")
    } else {
        throw TestFailure.expectationFailed("expected unavailable context")
    }
}),
("view model clear frontmost path falls back to global", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let personal = try GitProfile(
        id: "personal",
        displayName: "Personal",
        gitUserName: "Me",
        gitUserEmail: "me@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let work = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "Work",
        gitUserEmail: "work@example.com",
        sshKeyPath: "~/.ssh/id_work",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: false
    )
    try ProfileStore(fileURL: storeURL).save(ProfileStoreData(
        profiles: [personal, work],
        rules: [
            try FolderRule(id: "w1", path: "/Users/me/Work", profileId: "work", matchMode: .folderTree, enabled: true)
        ]
    ))
    let viewModel = AppViewModel(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        gitConfigInstaller: nil
    )
    viewModel.applyFrontmostPath("/Users/me/Work", source: .finder)
    viewModel.applyFrontmostClearedToGlobal()
    if case let .global(name) = viewModel.contextPresentation.kind {
        try expect(name == "Personal", "cleared context is global active")
    } else {
        throw TestFailure.expectationFailed("expected global context")
    }
}),
```

- [ ] **Step 2: Verify red**

```bash
swift run SwitchCommitCoreTestRunner
```

Expected: missing presentation types / view-model APIs.

- [ ] **Step 3: Implement presentation + view model APIs**

`FolderContextPresentation.swift`:

```swift
import Foundation
import SwitchCommitCore

public enum FrontmostPathSource: String, Equatable, Sendable {
    case finder
    case terminal
    case iterm
    case cursor
    case vsCode
}

public struct FolderAssignmentRow: Equatable, Identifiable, Sendable {
    public var id: String
    public var path: String
    public var matchMode: FolderRuleMatchMode

    public init(id: String, path: String, matchMode: FolderRuleMatchMode) {
        self.id = id
        self.path = path
        self.matchMode = matchMode
    }
}

public struct FolderContextPresentation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case folder(path: String, profileDisplayName: String)
        case global(profileDisplayName: String)
        case unavailable(reason: String)
    }

    public var kind: Kind
    public var menuTitle: String
    public var menuHeader: String

    public static func from(
        resolution: FolderRuleResolution,
        path: String?,
        unavailableReason: String?
    ) -> FolderContextPresentation {
        if let unavailableReason {
            return FolderContextPresentation(
                kind: .unavailable(reason: unavailableReason),
                menuTitle: resolution.profile?.displayName ?? "Switch Commit",
                menuHeader: "Context: unavailable (\(unavailableReason))"
            )
        }
        switch resolution.kind {
        case .folderRule:
            let name = resolution.profile?.displayName ?? "Unknown"
            let displayPath = path ?? resolution.rule?.path ?? ""
            return FolderContextPresentation(
                kind: .folder(path: displayPath, profileDisplayName: name),
                menuTitle: "\(name) · \(shortPath(displayPath))",
                menuHeader: "Context: \(displayPath) → \(name)"
            )
        case .global:
            let name = resolution.profile?.displayName ?? "No profile"
            return FolderContextPresentation(
                kind: .global(profileDisplayName: name),
                menuTitle: name,
                menuHeader: "Context: Global → \(name)"
            )
        }
    }

    private static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

public protocol FrontmostPathProviding: AnyObject {
    func currentFrontmostPath() -> (path: String, source: FrontmostPathSource)?
}
```

In `AppViewModel` add:

```swift
@Published public private(set) var folderAssignmentsForSelectedProfile: [FolderAssignmentRow]
@Published public private(set) var pendingFolderMatchMode: FolderRuleMatchMode
@Published public private(set) var contextPresentation: FolderContextPresentation
@Published public var isShowingFolderRuleMoveConfirmation: Bool
@Published public private(set) var pendingFolderRulePath: String?

// sync folderAssignmentsForSelectedProfile whenever selection/profiles/rules change
// methods:
// setPendingFolderMatchMode(_:)
// addFolderRuleForSelectedProfile(path:forceMove:)
// removeFolderRule(id:)
// confirmPendingFolderRuleMove()
// cancelPendingFolderRuleMove()
// applyFrontmostPath(_ path:source:)
// applyFrontmostUnavailable(reason:)
// applyFrontmostClearedToGlobal()
```

Behavior notes:

- `addFolderRuleForSelectedProfile` catches `pathOwnedByOtherProfile`, stores pending path, sets `isShowingFolderRuleMoveConfirmation = true`.
- `confirmPendingFolderRuleMove` retries with `forceMove: true`.
- `applyFrontmostPath` resolves via `FolderRuleResolver` using manager rules/profiles/active id; updates `contextPresentation`; bumps `menuContentRevision`; **must not** call `switchGlobalProfile`.
- `applyFrontmostClearedToGlobal` sets global presentation for the active profile (unsupported frontmost app).
- Initial `contextPresentation` = global for active profile.

- [ ] **Step 4: Verify green**

```bash
swift run SwitchCommitCoreTestRunner
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitchCommitAppLogic/FolderContextPresentation.swift \
  Sources/SwitchCommitAppLogic/AppViewModel.swift \
  Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "$(cat <<'EOF'
feat: expose folder assignments and live context in view model

Surface per-account folder rows and frontmost-path context without mutating the global active profile.
EOF
)"
```

---

### Task 4: Settings Folders UI

**Files:**
- Modify: `Sources/SwitchCommitApp/SettingsView.swift`

- [ ] **Step 1: Add Folders section under `accountForm`**

In `accountDetail`, after `accountForm`, before `Spacer()`:

```swift
folderAssignmentsSection
```

Implement:

- Header `Folders` + match-mode `Picker` bound to `pendingFolderMatchMode` (Folder tree / Single repo)
- `+` button → `NSOpenPanel` directories → `viewModel.addFolderRuleForSelectedProfile(path: url.path)`
- List of `folderAssignmentsForSelectedProfile` with path, mode badge, trash button → `removeFolderRule`
- Empty: `No folder assignments`
- `.alert` for move confirmation bound to `isShowingFolderRuleMoveConfirmation`

Keep English UI strings consistent with the rest of Settings.

- [ ] **Step 2: Build**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwitchCommitApp/SettingsView.swift
git commit -m "$(cat <<'EOF'
feat: list and edit folder assignments in Settings

Show strict per-account folder rules under account details with add, remove, and move confirmation.
EOF
)"
```

---

### Task 5: Frontmost monitor + menu bar wiring

**Files:**
- Create: `Sources/SwitchCommitApp/FrontmostPathProviders.swift`
- Create: `Sources/SwitchCommitApp/FrontmostContextMonitor.swift`
- Modify: `Sources/SwitchCommitApp/SwitchCommitApp.swift`

- [ ] **Step 1: Implement providers**

`FrontmostPathProviders.swift` responsibilities:

- Read frontmost bundle id via `NSWorkspace.shared.frontmostApplication`.
- Finder: AppleScript / Scripting Bridge for target of front window; map to POSIX path.
- Terminal.app: AppleScript tty of selected tab → `lsof` cwd (local commands only).
- iTerm2: AppleScript session path if available; else degraded.
- Cursor / VS Code: best-effort (window title path parse and/or related process cwd); on failure return `nil` so monitor can call unavailable only when frontmost is a supported app but path cannot be read; for unsupported apps call `applyFrontmostUnavailable` is **wrong** — instead clear to global by applying no path:

Prefer monitor logic:

```swift
if let result = provider.currentFrontmostPath() {
  viewModel.applyFrontmostPath(result.path, source: result.source)
} else if provider.frontmostIsSupportedContextApp {
  viewModel.applyFrontmostUnavailable(reason: "Could not read folder")
} else {
  viewModel.applyFrontmostClearedToGlobal()
}
```

Never network. Catch Automation errors and degrade.

- [ ] **Step 2: Implement monitor**

```swift
@MainActor
final class FrontmostContextMonitor {
    private let viewModel: AppViewModel
    private var timer: Timer?

    init(viewModel: AppViewModel) { self.viewModel = viewModel }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() { /* call providers + viewModel updates */ }
}
```

- [ ] **Step 3: Wire app + menu**

In `SwitchCommitApp`:

- Hold `FrontmostContextMonitor`, start in `applicationDidFinishLaunching`.
- `buildMenu()`: first item = `viewModel.contextPresentation.menuHeader` (disabled), then separator, then existing profile list (keep `Active:` or replace with context header — prefer context header as primary; keep profile checks below).
- Update status item button: prefer `imagePosition = .imageLeading` and `title = viewModel.contextPresentation.menuTitle` truncated reasonably, or tooltip = menuTitle if title too long. Keep symbol image.
- Observe `menuContentRevision` as today so poll updates refresh menu/title.

- [ ] **Step 4: Verify**

```bash
swift run SwitchCommitCoreTestRunner
swift build
```

Expected: tests + build pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitchCommitApp/FrontmostPathProviders.swift \
  Sources/SwitchCommitApp/FrontmostContextMonitor.swift \
  Sources/SwitchCommitApp/SwitchCommitApp.swift \
  Sources/SwitchCommitAppLogic/AppViewModel.swift
git commit -m "$(cat <<'EOF'
feat: show live frontmost folder context in menu bar

Poll Finder and terminal apps for the focused path and preview the matching folder rule without switching the global profile.
EOF
)"
```

---

### Task 6: Docs

**Files:**
- Modify: `README.md`
- Modify: `docs/future-features.md`
- Modify: latest relevant file under `docs/release-notes/` (create a short entry in the newest notes file if one exists for the pending release; otherwise add a bullet under an existing unreleased section if present)

- [ ] **Step 1: README**

Add a short subsection:

```markdown
### Folder Accounts

Assign folders to an account in Settings → Accounts → Folders. Git uses managed `includeIf` rules so repositories under those paths pick that identity automatically. The menu bar previews the account for the frontmost Finder or terminal folder. Reading Terminal/Finder paths may require macOS Automation permission; denial falls back to the global account preview.
```

- [ ] **Step 2: future-features**

Update section 4 status to something like:

`Status: w trakcie / design gotowy (Settings lista + live context); CLI poza zakresem`

Keep point 1 (notifications) separate.

- [ ] **Step 3: Verify + commit**

```bash
swift run SwitchCommitCoreTestRunner
swift build
git add README.md docs/future-features.md docs/release-notes
git commit -m "$(cat <<'EOF'
docs: document folder accounts and live context

Describe Settings folder assignments, includeIf switching, menu-bar preview, and Automation fallback.
EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `includeIf` switching unchanged (no focus-driven git config) | 2, 5 |
| Settings list only strict folder rules (not global) | 2, 3, 4 |
| Add/remove folder + default tree + mode toggle | 2, 3, 4 |
| Conflict move with confirmation | 2, 3, 4 |
| Longest prefix wins / disabled ignored | 1 |
| Path normalization | 1, 2 |
| Live poll ~2s frontmost focus | 5 |
| Finder + Terminal + iTerm + Cursor/VS Code | 5 |
| Degraded Automation mode | 5 |
| Menu header + title | 5 |
| Core tests via test runner | 1–3 |
| Docs / future-features | 6 |
| CLI out of scope | — |

## Notes for implementers

- Do not edit `Sources/GitAccountSwitcher*`.
- Do not add XCTest.
- Do not add network calls, telemetry, or Notification Center mismatch alerts.
- Cursor/VS Code CWD is best-effort; failures must not crash.
- Always run `swift run SwitchCommitCoreTestRunner` and `swift build` before claiming done.
