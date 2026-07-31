# Switch Commit CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `switch-commit` CLI that shares `SwitchCommitCore` persistence with the menu bar app, supports full profile/folder management plus `--json`, a simple interactive TUI, PATH install via pkg + Settings, and English human-readable colored output.

**Architecture:** Add pure Core helpers (`ProfileReferenceResolver`, `FolderRuleResolver`, `SwitchCommitSession`, shared default store path) used by a new SPM executable `switch-commit` built with `swift-argument-parser` and a small custom ANSI/TUI layer. No XPC. Release embeds the CLI binary in the app bundle; a `.pkg` inside the DMG installs `/usr/local/bin/switch-commit`, and Settings can repair the link.

**Tech Stack:** Swift 6.2, SwiftPM, `swift-argument-parser` (≥1.8.2), Foundation, existing `SwitchCommitCoreTestRunner`, bash/`pkgbuild`/`productbuild` for installer.

**Spec:** `docs/superpowers/specs/2026-07-31-switch-commit-cli-design.md`

**Worktree:** Implement on an isolated git worktree from `codex/switch-commit-cli` (or continue from `codex/switch-commit-cli-design` after plan commit). Prefer `.worktrees/` if present and gitignored.

---

## File Structure

- Create: `Sources/SwitchCommitCore/SwitchCommitPaths.swift` — default `profiles.json` URL under `~/.config/git-account-switcher/`
- Create: `Sources/SwitchCommitCore/ProfileReferenceResolver.swift` — resolve profile by id or display name
- Create: `Sources/SwitchCommitCore/FolderRuleResolver.swift` — normalize paths + longest-prefix match
- Create: `Sources/SwitchCommitCore/SwitchCommitSession.swift` — load/save/switch/CRUD/folder/doctor facade for CLI (and reusable by tests)
- Create: `Sources/SwitchCommitCore/CLIOutput.swift` — human + JSON formatters, color policy, exit codes (testable without ArgumentParser)
- Modify: `Sources/SwitchCommitCore/ProfileSettingsManager.swift` — folder rule CRUD helpers if not already present; keep UI selection semantics intact
- Modify: `Sources/SwitchCommitAppLogic/AppViewModel.swift` — use `SwitchCommitPaths.defaultProfilesURL`
- Modify: `Package.swift` — ArgumentParser dependency + `switch-commit` executable product/target
- Create: `Sources/SwitchCommitCLI/main.swift` — `@main` entry
- Create: `Sources/SwitchCommitCLI/SwitchCommitCommand.swift` — root command, global flags, no-args TUI routing
- Create: `Sources/SwitchCommitCLI/Commands/*.swift` — `List`, `Status`, `Use`, `Show`, `Add`, `Edit`, `Delete`, `Folder`, `Doctor`, `Version`
- Create: `Sources/SwitchCommitCLI/InteractiveProfileMenu.swift` — simple ANSI list TUI
- Create: `Sources/SwitchCommitCLI/CLIRuntime.swift` — builds `SwitchCommitSession` for real home paths
- Create: `Sources/SwitchCommitApp/CLIInstallManager.swift` — symlink/wrapper install to `/usr/local/bin/switch-commit` with admin prompt
- Modify: `Sources/SwitchCommitApp/SettingsView.swift` — General tab Install / Reinstall CLI
- Modify: `Sources/SwitchCommitAppLogic/AppViewModel.swift` — CLI install presentation + actions
- Modify: `Scripts/build-release.sh` — build/copy CLI into app; produce pkg+DMG
- Create: `Scripts/macos/cli-launch.sh` — thin wrapper that execs CLI inside `.app`
- Create: `Scripts/macos/distribution.xml` / component plist as needed for `productbuild`
- Modify: `Sources/SwitchCommitCoreTestRunner/main.swift` — tests for all new Core/CLIOutput behavior
- Modify: `README.md`, `docs/future-features.md`, `docs/release-notes/v0.3.0.md` (or next version)

---

### Task 1: Shared default store path

**Files:**
- Create: `Sources/SwitchCommitCore/SwitchCommitPaths.swift`
- Modify: `Sources/SwitchCommitAppLogic/AppViewModel.swift`
- Test: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing path test**

Add near profile store tests:

```swift
("switch commit paths default profiles url lives under managed config dir", {
    let url = SwitchCommitPaths.defaultProfilesURL(homeDirectory: URL(fileURLWithPath: "/Users/demo"))
    try expect(
        url.path == "/Users/demo/.config/git-account-switcher/profiles.json",
        "default profiles path should match managed config layout"
    )
}),
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run SwitchCommitCoreTestRunner`
Expected: FAIL mentioning `SwitchCommitPaths`

- [ ] **Step 3: Implement paths + wire AppViewModel**

```swift
import Foundation

public enum SwitchCommitPaths: Sendable {
    public static func defaultProfilesURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("git-account-switcher", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }
}
```

Replace `AppViewModel.defaultProfilesURL()` body with `SwitchCommitPaths.defaultProfilesURL()`.

- [ ] **Step 4: Run tests**

Run: `swift run SwitchCommitCoreTestRunner`
Expected: PASS for the new test

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitchCommitCore/SwitchCommitPaths.swift Sources/SwitchCommitAppLogic/AppViewModel.swift Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "feat: share default profiles path for CLI and app"
```

---

### Task 2: Profile reference resolver

**Files:**
- Create: `Sources/SwitchCommitCore/ProfileReferenceResolver.swift`
- Test: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing resolver tests**

```swift
("profile reference resolver matches id exactly", {
    let profiles = [
        try GitProfile(id: "work", displayName: "Work", gitUserName: "W", gitUserEmail: "w@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: true),
        try GitProfile(id: "personal", displayName: "Personal", gitUserName: "P", gitUserEmail: "p@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: false)
    ]
    let resolved = try ProfileReferenceResolver.resolve("work", in: profiles)
    try expect(resolved.id == "work", "id lookup should win")
}),
("profile reference resolver matches display name case-insensitively", {
    let profiles = [
        try GitProfile(id: "work", displayName: "Work", gitUserName: "W", gitUserEmail: "w@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: true)
    ]
    let resolved = try ProfileReferenceResolver.resolve("work", in: profiles)
    try expect(resolved.displayName == "Work", "name lookup should be case-insensitive")
}),
("profile reference resolver errors on unknown and ambiguous names", {
    let profiles = [
        try GitProfile(id: "a", displayName: "Work", gitUserName: "A", gitUserEmail: "a@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: true),
        try GitProfile(id: "b", displayName: "work", gitUserName: "B", gitUserEmail: "b@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: false)
    ]
    try expectThrowsAny({ _ = try ProfileReferenceResolver.resolve("missing", in: profiles) }, "unknown should throw")
    try expectThrowsAny({ _ = try ProfileReferenceResolver.resolve("work", in: profiles) }, "ambiguous display names should throw")
}),
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `swift run SwitchCommitCoreTestRunner`

- [ ] **Step 3: Implement resolver**

```swift
import Foundation

public enum ProfileReferenceError: Error, Equatable, Sendable {
    case notFound(String)
    case ambiguous(String, candidates: [String])
}

public enum ProfileReferenceResolver: Sendable {
    public static func resolve(_ reference: String, in profiles: [GitProfile]) throws -> GitProfile {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let byId = profiles.first(where: { $0.id == trimmed }) {
            return byId
        }
        let matches = profiles.filter { $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }
        switch matches.count {
        case 1:
            return matches[0]
        case 0:
            throw ProfileReferenceError.notFound(trimmed)
        default:
            throw ProfileReferenceError.ambiguous(trimmed, candidates: matches.map(\.id).sorted())
        }
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitchCommitCore/ProfileReferenceResolver.swift Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "feat: resolve CLI profile references by id or name"
```

---

### Task 3: Folder rule resolver

**Files:**
- Create: `Sources/SwitchCommitCore/FolderRuleResolver.swift`
- Test: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing resolver tests**

```swift
("folder rule resolver prefers longest enabled prefix for folder trees", {
    let work = try FolderRule(id: "r1", path: "/Users/demo/Dev", profileId: "work", matchMode: .folderTree, enabled: true)
    let acme = try FolderRule(id: "r2", path: "/Users/demo/Dev/acme", profileId: "acme", matchMode: .folderTree, enabled: true)
    let match = FolderRuleResolver.match(
        path: "/Users/demo/Dev/acme/repo",
        rules: [work, acme],
        homeDirectory: URL(fileURLWithPath: "/Users/demo")
    )
    try expect(match?.id == "r2", "longest prefix should win")
}),
("folder rule resolver singleRepo matches only exact path", {
    let rule = try FolderRule(id: "r1", path: "/Users/demo/repo", profileId: "work", matchMode: .singleRepo, enabled: true)
    let hit = FolderRuleResolver.match(path: "/Users/demo/repo", rules: [rule], homeDirectory: URL(fileURLWithPath: "/Users/demo"))
    let miss = FolderRuleResolver.match(path: "/Users/demo/repo/sub", rules: [rule], homeDirectory: URL(fileURLWithPath: "/Users/demo"))
    try expect(hit?.id == "r1", "exact path should match")
    try expect(miss == nil, "descendant should not match singleRepo")
}),
("folder rule resolver ignores disabled rules", {
    let rule = try FolderRule(id: "r1", path: "/Users/demo/Dev", profileId: "work", matchMode: .folderTree, enabled: false)
    let match = FolderRuleResolver.match(path: "/Users/demo/Dev/x", rules: [rule], homeDirectory: URL(fileURLWithPath: "/Users/demo"))
    try expect(match == nil, "disabled rules must not match")
}),
```

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement `FolderRuleResolver`**

Implement `normalize(_:homeDirectory:)` that expands `~`, standardizes, and strips trailing `/` except root. Matching:

- `folderTree`: normalized path == rule path OR has prefix `rulePath + "/"`
- `singleRepo`: exact normalized path equality
- among matches, choose longest `rule.path` (after normalize)

```swift
public enum FolderRuleResolver: Sendable {
    public static func normalize(_ path: String, homeDirectory: URL) -> String { /* ... */ }

    public static func match(
        path: String,
        rules: [FolderRule],
        homeDirectory: URL
    ) -> FolderRule? { /* ... */ }
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitchCommitCore/FolderRuleResolver.swift Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "feat: resolve folder rules for CLI status context"
```

---

### Task 4: Folder rule CRUD on ProfileSettingsManager

**Files:**
- Modify: `Sources/SwitchCommitCore/ProfileSettingsManager.swift`
- Test: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing CRUD tests**

Use temp `ProfileStore` + optional `ManagedGitConfigInstaller(homeDirectory:)` like existing manager tests:

```swift
("profile settings manager adds folder rule and reapplies config", {
    let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let work = try GitProfile(id: "work", displayName: "Work", gitUserName: "W", gitUserEmail: "w@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: true)
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        seedProfiles: [work],
        gitConfigInstaller: ManagedGitConfigInstaller(homeDirectory: temporaryDirectory)
    )
    let rule = try manager.addFolderRule(
        path: temporaryDirectory.appendingPathComponent("Dev").path,
        profileId: "work",
        matchMode: .folderTree
    )
    try expect(manager.rules.contains(where: { $0.id == rule.id }), "rule should be in memory")
    let loaded = try ProfileStore(fileURL: storeURL).load()
    try expect(loaded.rules.count == 1, "rule should persist")
}),
("profile settings manager moves folder rule on confirmed takeover", {
    // seed two profiles + rule on personal; add same path to work with moveIfOwned=true; assert profileId == work
}),
("profile settings manager lists rules for one profile only", {
    // add rules for work and personal; rules(forProfileId: "work") excludes personal
}),
```

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement manager APIs**

Add:

```swift
public func rules(forProfileId profileId: String) -> [FolderRule]

@discardableResult
public func addFolderRule(
    path: String,
    profileId: String,
    matchMode: FolderRuleMatchMode = .folderTree,
    moveIfOwned: Bool = false
) throws -> FolderRule

public func removeFolderRule(id: String) throws
public func removeFolderRule(path: String) throws
```

Semantics:

- Normalize path via `FolderRuleResolver.normalize`
- One path → at most one rule; if owned by another profile and `moveIfOwned == false`, throw a dedicated error (add `SwitchCommitError.folderRuleOwnedByOtherProfile` or a small `FolderRuleMutationError`)
- Persist + `applyGitConfig()` after mutations
- Generate safe unique rule ids (`rule-1`, …) with existing identifier validation

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitchCommitCore/ProfileSettingsManager.swift Sources/SwitchCommitCore/Models.swift Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "feat: add folder rule CRUD for CLI and settings"
```

---

### Task 5: SwitchCommitSession facade

**Files:**
- Create: `Sources/SwitchCommitCore/SwitchCommitSession.swift`
- Test: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing session tests**

```swift
("switch commit session lists profiles and switches active", {
    let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let personal = try GitProfile(id: "personal", displayName: "Personal", gitUserName: "P", gitUserEmail: "p@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: true)
    let work = try GitProfile(id: "work", displayName: "Work", gitUserName: "W", gitUserEmail: "w@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: false)
    try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [personal, work], rules: []))
    let session = try SwitchCommitSession(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        gitConfigInstaller: ManagedGitConfigInstaller(homeDirectory: temporaryDirectory),
        homeDirectory: temporaryDirectory
    )
    try expect(session.profiles.count == 2, "should load profiles")
    try session.use(reference: "work")
    try expect(session.activeProfile?.id == "work", "use should switch active")
    let global = try String(
        contentsOf: temporaryDirectory.appendingPathComponent(".config/git-account-switcher/global.gitconfig"),
        encoding: .utf8
    )
    try expect(global.contains("w@example.com"), "installer should rewrite global identity")
}),
("switch commit session status reports folder context", {
    // save rule pointing at temp/Dev; status(path:) source == folder with matching profile
}),
```

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement session**

`SwitchCommitSession` wraps `ProfileSettingsManager` (or owns the same state) and exposes:

```swift
public struct StatusSnapshot: Equatable, Sendable {
    public var activeProfile: GitProfile?
    public var contextProfile: GitProfile?
    public var contextPath: String?
    public var contextSource: ContextSource // global | folder | none
}

public final class SwitchCommitSession {
    public init(profileStore:keychainStore:gitConfigInstaller:homeDirectory:commandRunner:) throws
    public var profiles: [GitProfile] { get }
    public var rules: [FolderRule] { get }
    public var activeProfile: GitProfile? { get }
    public func use(reference: String) throws
    public func status(path: String?) -> StatusSnapshot
    public func show(reference: String) throws -> GitProfile
    public func addProfile(...) throws -> GitProfile
    public func editProfile(reference: String, ...) throws -> GitProfile
    public func deleteProfile(reference: String) throws
    public func addFolderRule(...) throws -> FolderRule
    public func removeFolderRule(...) throws
    public func doctor(path: String?) -> DiagnosticsReport
}
```

`doctor` calls `DiagnosticsService.inspectGitIdentity` only (local). Do not call host SSH network tests unless a future explicit flag is added (out of v1 default `doctor`).

Factory for production:

```swift
public static func live() throws -> SwitchCommitSession {
    try SwitchCommitSession(
        profileStore: ProfileStore(fileURL: SwitchCommitPaths.defaultProfilesURL()),
        keychainStore: KeychainStore(),
        gitConfigInstaller: ManagedGitConfigInstaller(),
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser
    )
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitchCommitCore/SwitchCommitSession.swift Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "feat: add SwitchCommitSession facade for CLI"
```

---

### Task 6: CLI output helpers (human + JSON)

**Files:**
- Create: `Sources/SwitchCommitCore/CLIOutput.swift`
- Test: `Sources/SwitchCommitCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing formatter tests**

```swift
("cli output json list never contains credential secrets", {
    let profile = try GitProfile(
        id: "work",
        displayName: "Work",
        gitUserName: "W",
        gitUserEmail: "w@example.com",
        accessMethod: .https,
        sshKeyPath: "",
        hosts: ["github.com"],
        httpsCredentialRef: "git-account-switcher.work.https",
        isDefault: true
    )
    let json = CLIOutput.jsonList(profiles: [profile], activeProfileId: "work")
    try expect(json.contains("\"id\":\"work\""), "json should include id")
    try expect(json.contains("git-account-switcher.work.https"), "credential ref id is allowed")
    try expect(!json.lowercased().contains("token"), "must not invent token fields")
}),
("cli output respects no color", {
    let text = CLIOutput.humanStatus(
        snapshot: /* minimal StatusSnapshot */,
        style: CLIOutput.Style(colorEnabled: false)
    )
    try expect(!text.contains("\u{001B}["), "no ANSI when disabled")
}),
("cli output json error envelope", {
    let json = CLIOutput.jsonError("unknown profile")
    try expect(json.contains("\"ok\":false"), "error envelope required")
    try expect(json.contains("unknown profile"), "message required")
}),
```

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement `CLIOutput`**

Include:

```swift
public enum CLIExitCode: Int32 {
    case success = 0
    case usage = 1
    case failure = 2
}

public struct CLIOutput {
    public struct Style: Sendable {
        public var colorEnabled: Bool
        public static func detect(noColorFlag: Bool, isTTY: Bool, env: [String: String] = ProcessInfo.processInfo.environment) -> Style {
            if noColorFlag || env["NO_COLOR"] != nil || !isTTY { return Style(colorEnabled: false) }
            return Style(colorEnabled: true)
        }
    }
    // humanList, humanStatus, humanShow, jsonList, jsonStatus, jsonShow, jsonError, jsonOK...
}
```

Stable JSON keys: `ok`, `error`, `profiles`, `activeProfileId`, `profile`, `status`, `rules`. Never emit Keychain secret values.

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitchCommitCore/CLIOutput.swift Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "feat: add deterministic CLI human and JSON formatters"
```

---

### Task 7: Package executable scaffold

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SwitchCommitCLI/main.swift`
- Create: `Sources/SwitchCommitCLI/SwitchCommitCommand.swift`
- Create: `Sources/SwitchCommitCLI/CLIRuntime.swift`

- [ ] **Step 1: Add dependency and target**

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")
],
products: [
    // existing...
    .executable(name: "switch-commit", targets: ["SwitchCommitCLI"])
],
targets: [
    // existing...
    .executableTarget(
        name: "SwitchCommitCLI",
        dependencies: [
            "SwitchCommitCore",
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]
    )
]
```

- [ ] **Step 2: Minimal root command**

`main.swift`:

```swift
import ArgumentParser

@main
struct SwitchCommitMain {
    static func main() {
        SwitchCommitCommand.main()
    }
}
```

`SwitchCommitCommand.swift`: root `ParsableCommand` with `commandName: "switch-commit"`, global `--json`, `--no-color`, default run:

- if `CommandLine.arguments.count == 1` and stdin/stdout TTY → later TUI (for now print help / version stub)
- if no args and non-TTY → stderr help, exit 1

Include stub `struct Version: ParsableCommand`.

- [ ] **Step 3: Build**

Run: `swift build --product switch-commit`
Expected: build succeeds

Run: `swift run switch-commit --help`
Expected: help text mentioning Switch Commit

- [ ] **Step 4: Commit**

```bash
git add Package.swift Package.resolved Sources/SwitchCommitCLI
git commit -m "feat: scaffold switch-commit executable with ArgumentParser"
```

---

### Task 8: Read commands — list, status, show, use

**Files:**
- Create: `Sources/SwitchCommitCLI/Commands/ListCommand.swift`
- Create: `Sources/SwitchCommitCLI/Commands/StatusCommand.swift`
- Create: `Sources/SwitchCommitCLI/Commands/ShowCommand.swift`
- Create: `Sources/SwitchCommitCLI/Commands/UseCommand.swift`
- Modify: `Sources/SwitchCommitCLI/SwitchCommitCommand.swift`
- Test: keep behavioral coverage in Core session/output tests; add a pure mapping test if command exit mapping is extracted

- [ ] **Step 1: Implement commands calling `CLIRuntime.session()`**

Each command:

1. Build style from flags + `isatty`
2. Call session
3. Print human or JSON
4. Map `ProfileReferenceError` → exit 1, I/O → exit 2 via `CLIRuntime.terminate`

`status` accepts optional `--path` defaulting to `FileManager.default.currentDirectoryPath`.

`use` prints confirmation line / JSON ok on success.

- [ ] **Step 2: Manual smoke**

```bash
swift run switch-commit list
swift run switch-commit status
swift run switch-commit list --json
```

Expected: runs against real store (may be empty); `--json` is valid JSON

- [ ] **Step 3: Run full tests + build**

```bash
swift run SwitchCommitCoreTestRunner
swift build
```

- [ ] **Step 4: Commit**

```bash
git add Sources/SwitchCommitCLI
git commit -m "feat: add list status show and use CLI commands"
```

---

### Task 9: Mutation commands — add, edit, delete

**Files:**
- Create: `Sources/SwitchCommitCLI/Commands/AddCommand.swift`
- Create: `Sources/SwitchCommitCLI/Commands/EditCommand.swift`
- Create: `Sources/SwitchCommitCLI/Commands/DeleteCommand.swift`

- [ ] **Step 1: Implement flag-driven mutations**

Required flags for non-interactive `add`:

- `--name`, `--git-name`, `--git-email`
- `--access ssh|https` (default `https` for easier CLI)
- `--ssh-key` required when ssh
- `--host` (repeatable, default `github.com`)

`edit` takes reference + optional same flags.

`delete` takes reference; requires `--yes` or interactive `y/N` confirmation on TTY; non-TTY without `--yes` → exit 1.

Never accept raw token values as flags; only optional `--https-credential-ref` identifier string.

- [ ] **Step 2: Core tests for session add/edit/delete if not already covered**

Add session tests that mutate temp store.

- [ ] **Step 3: Verify**

```bash
swift run SwitchCommitCoreTestRunner
swift build --product switch-commit
```

- [ ] **Step 4: Commit**

```bash
git add Sources/SwitchCommitCLI Sources/SwitchCommitCoreTestRunner/main.swift Sources/SwitchCommitCore/SwitchCommitSession.swift
git commit -m "feat: add profile CRUD commands to switch-commit CLI"
```

---

### Task 10: Folder commands + doctor

**Files:**
- Create: `Sources/SwitchCommitCLI/Commands/FolderCommand.swift`
- Create: `Sources/SwitchCommitCLI/Commands/DoctorCommand.swift`

- [ ] **Step 1: Implement `folder list|add|remove`**

```text
switch-commit folder list [--json]
switch-commit folder add <path> --profile <ref> [--mode folder-tree|single-repo] [--yes]
switch-commit folder remove <path-or-id> [--yes]
```

On takeover without `--yes`, print who owns the path and exit 1 with message to pass `--yes`.

- [ ] **Step 2: Implement `doctor`**

Print `DiagnosticsReport` values/warnings (human table or JSON). Local only.

- [ ] **Step 3: Tests for folder takeover messaging via session errors**

- [ ] **Step 4: Verify + commit**

```bash
swift run SwitchCommitCoreTestRunner
swift build
git add Sources/SwitchCommitCLI Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "feat: add folder and doctor CLI commands"
```

---

### Task 11: Interactive TUI (no-args)

**Files:**
- Create: `Sources/SwitchCommitCLI/InteractiveProfileMenu.swift`
- Modify: `Sources/SwitchCommitCLI/SwitchCommitCommand.swift`

- [ ] **Step 1: Implement simple list UI**

When no subcommand and stdout/stdin are TTYs:

- Draw panel header `switch-commit · profiles`
- Show profiles with email; mark active with `●`
- Read raw terminal mode (termios) for arrow keys / enter / `q` / `a` / `d`
- Enter → `session.use`
- `q` → exit 0
- `d` → confirm delete
- `a` → prompt fields then `addProfile`

Disable TUI when `--json` is passed with no subcommand (print usage exit 1).

Keep implementation small; ASCII fallbacks if needed. No external TUI package.

- [ ] **Step 2: Smoke manually in Terminal.app**

`swift run switch-commit` → menu appears; `q` quits

- [ ] **Step 3: Commit**

```bash
git add Sources/SwitchCommitCLI
git commit -m "feat: add interactive profile menu for switch-commit"
```

---

### Task 12: Settings Install / Reinstall CLI

**Files:**
- Create: `Sources/SwitchCommitApp/CLIInstallManager.swift`
- Modify: `Sources/SwitchCommitAppLogic/AppViewModel.swift`
- Modify: `Sources/SwitchCommitApp/SettingsView.swift`
- Test: `Sources/SwitchCommitCoreTestRunner/main.swift` for pure path helpers if extracted; AppKit installer can use a protocol

- [ ] **Step 1: Define install contract**

```swift
public protocol CLIInstalling: Sendable {
    var statusMessage: String { get }
    func installOrRepair() throws
}

public struct CLIInstallPaths: Sendable {
    public static let pathLink = URL(fileURLWithPath: "/usr/local/bin/switch-commit")
    public static func bundledCLI(mainBundle: Bundle = .main) -> URL? {
        mainBundle.bundleURL
            .appendingPathComponent("Contents/MacOS/switch-commit")
    }
}
```

`CLIInstallManager` creates `/usr/local/bin` if needed and symlinks (or installs wrapper script) to bundled CLI. Use `osascript` admin privileges when permission denied — same spirit as other macOS apps; keep implementation localized in App target.

- [ ] **Step 2: Settings General UI**

Below Launch at Login:

- Button `Install CLI` / `Reinstall CLI`
- Caption: installs `switch-commit` to `/usr/local/bin` pointing at the app bundle
- Status text from view model

- [ ] **Step 3: Wire view model messages**

- [ ] **Step 4: Build app target**

```bash
swift build --product SwitchCommitApp
swift run SwitchCommitCoreTestRunner
```

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitchCommitApp Sources/SwitchCommitAppLogic Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "feat: install switch-commit CLI from Settings"
```

---

### Task 13: Release packaging — embed CLI + pkg in DMG

**Files:**
- Modify: `Scripts/build-release.sh`
- Create: `Scripts/macos/cli-launch.sh`
- Create: `Scripts/macos/component.plist` (optional)
- Create: `Scripts/macos/distribution.xml`
- Test: extend test runner string checks on `build-release.sh` like existing release script tests

- [ ] **Step 1: Write failing script-content tests**

In test runner (pattern used for release scripts):

```swift
("release script builds and embeds switch-commit CLI", {
    let source = try String(contentsOfFile: "Scripts/build-release.sh", encoding: .utf8)
    try expect(source.contains("switch-commit"), "should build CLI product")
    try expect(source.contains("Contents/MacOS/switch-commit"), "should embed CLI in app bundle")
    try expect(source.contains("pkgbuild") || source.contains("productbuild"), "should produce installer pkg")
}),
```

- [ ] **Step 2: Update `build-release.sh`**

After app binary copy:

```bash
swift build -c release --product switch-commit
cp "${repo_root}/.build/release/switch-commit" "${app_bundle}/Contents/MacOS/switch-commit"
chmod 755 "${app_bundle}/Contents/MacOS/switch-commit"
codesign --force --sign - "${app_bundle}/Contents/MacOS/switch-commit"
```

Build a component pkg that:

1. Installs `Switch Commit.app` to `/Applications`
2. Runs postinstall (or installs a wrapper) creating `/usr/local/bin/switch-commit` → `/Applications/Switch Commit.app/Contents/MacOS/switch-commit`

Preferred wrapper content (`Scripts/macos/cli-launch.sh`):

```bash
#!/bin/bash
exec "/Applications/Switch Commit.app/Contents/MacOS/switch-commit" "$@"
```

DMG contents:

- `Switch Commit.app` (still allow drag install)
- `Install Switch Commit.pkg` (app + CLI PATH)
- short `README.txt` explaining pkg vs drag + Settings repair

Keep existing Sparkle feed/privacy behavior unchanged.

- [ ] **Step 3: Run script tests + dry-run build if feasible**

```bash
swift run SwitchCommitCoreTestRunner
# optional local: Scripts/build-release.sh 0.3.0-dev
```

- [ ] **Step 4: Commit**

```bash
git add Scripts README.md Sources/SwitchCommitCoreTestRunner/main.swift
git commit -m "feat: package switch-commit CLI into release DMG and pkg"
```

---

### Task 14: Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/future-features.md`
- Create: `docs/release-notes/v0.3.0.md` (or bump to the next real version used by release script)

- [ ] **Step 1: README section `## CLI`**

Document:

- `switch-commit` command cheat sheet
- `--json` / `--no-color`
- install via pkg vs Settings Install CLI
- broken symlink repair
- safety: no secrets, local doctor

- [ ] **Step 2: Mark future-features section 3 status as implemented / shipped with note**

- [ ] **Step 3: Release notes bullets**

- [ ] **Step 4: Final verification**

```bash
swift run SwitchCommitCoreTestRunner
swift build
swift build --product switch-commit
```

- [ ] **Step 5: Commit**

```bash
git add README.md docs/future-features.md docs/release-notes
git commit -m "docs: document switch-commit CLI install and commands"
```

---

## Spec Coverage Self-Check

| Spec requirement | Task(s) |
|---|---|
| Executable `switch-commit` on Core + ArgumentParser | 7–11 |
| Shared store / managed paths | 1, 5 |
| list/status/use/show/add/edit/delete | 8–9 |
| folder list/add/remove | 4, 10 |
| doctor local-only | 5, 10 |
| `--json`, `--no-color`, `NO_COLOR`, exit codes | 6–8 |
| Interactive TUI no-args | 11 |
| English copy | all CLI strings |
| pkg + `/usr/local/bin` + Settings install | 12–13 |
| README / future-features / release notes | 14 |
| Tests via CoreTestRunner + swift build | every task |
| No secrets / no XPC / no heavy TUI lib | architecture + 6, 11 |
| Worktree + `codex/` branch | execution handoff |

## Placeholder / Consistency Notes

- JSON error shape is always `{"ok":false,"error":"..."}` on stdout when `--json` (Task 6).
- Bundled CLI path is `Contents/MacOS/switch-commit` everywhere (Tasks 12–13).
- Session is the only mutation entry point for CLI commands (Tasks 5, 8–11).
