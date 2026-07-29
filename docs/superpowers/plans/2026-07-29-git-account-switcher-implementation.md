# Git Account Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-only macOS menu bar app that safely switches Git identities globally and per folder without overwriting user-managed Git or SSH configuration.

**Architecture:** Use a Swift Package with a testable `GitAccountSwitcherCore` library and a SwiftUI/AppKit `GitAccountSwitcherApp` executable. The core owns profile models, deterministic config generation, backup-aware file writes, and diagnostics with injectable command execution; the UI only calls core APIs and never talks to the network directly.

**Tech Stack:** Swift 6.2, Swift Package Manager, SwiftUI `MenuBarExtra`, Foundation, Security framework for Keychain references, custom local test runner executable.

---

## File Structure

- `Package.swift`: Swift package manifest with a library, executable app, and tests.
- `README.md`: local-only privacy and safety contract plus build/test commands.
- `Sources/GitAccountSwitcherCore/Models.swift`: `GitProfile`, `FolderRule`, `ManagedPaths`, and validation errors.
- `Sources/GitAccountSwitcherCore/ProfileStore.swift`: JSON profile/rule persistence with no secrets stored.
- `Sources/GitAccountSwitcherCore/GitConfigGenerator.swift`: deterministic `.gitconfig` content generation.
- `Sources/GitAccountSwitcherCore/SSHConfigGenerator.swift`: deterministic SSH include generation.
- `Sources/GitAccountSwitcherCore/SafeFileWriter.swift`: backup-aware atomic writes constrained to managed paths.
- `Sources/GitAccountSwitcherCore/DiagnosticsService.swift`: local command diagnostics through injected runner.
- `Sources/GitAccountSwitcherCore/KeychainStore.swift`: Keychain wrapper storing secret payloads by profile-owned identifiers.
- `Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift`: macOS menu bar app entry point.
- `Sources/GitAccountSwitcherApp/AppViewModel.swift`: UI state and commands.
- `Sources/GitAccountSwitcherCoreTestRunner/main.swift`: focused local test runner for core behavior because this Command Line Tools install does not expose XCTest or Swift Testing.

## Security Invariants

- No telemetry, analytics, crash upload, auto-update, or background network calls.
- No secret values in JSON profile files or generated Git config.
- Only managed files are written by default: `~/.config/git-account-switcher/*` and `~/.ssh/git-account-switcher.conf`.
- Existing `~/.gitconfig` and `~/.ssh/config` are only modified by adding explicit include lines, after backup.
- Tests use temporary homes and must not read or write the real user home.
- SSH/GitHub network tests are manual user-triggered diagnostics only.

### Task 1: Swift Package Skeleton

**Files:**
- Create: `Package.swift`
- Create: `README.md`
- Create: `Sources/GitAccountSwitcherCore/Models.swift`
- Create: `Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift`
- Create: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write the failing model test**

```swift
import Testing
@testable import GitAccountSwitcherCore

@Suite("Models")
struct ModelsTests {
    @Test("Profile rejects empty commit identity")
    func profileRejectsEmptyCommitIdentity() throws {
        #expect(throws: GitAccountSwitcherError.emptyGitUserName) {
            try GitProfile(
                id: "personal",
                displayName: "Personal",
                gitUserName: "",
                gitUserEmail: "me@example.com",
                sshKeyPath: "/Users/me/.ssh/id_ed25519",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelsTests`

Expected: FAIL because `Package.swift` and `GitProfile` do not exist.

- [ ] **Step 3: Create the package and minimal model implementation**

Create `Package.swift` with a macOS 14 package, `GitAccountSwitcherCore` library, `GitAccountSwitcherApp` executable, and `GitAccountSwitcherCoreTests`.

Create `Models.swift` with:

```swift
import Foundation

public enum GitAccountSwitcherError: Error, Equatable {
    case emptyDisplayName
    case emptyGitUserName
    case emptyGitUserEmail
    case emptySSHKeyPath
    case emptyHost
}

public struct GitProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var displayName: String
    public var gitUserName: String
    public var gitUserEmail: String
    public var sshKeyPath: String
    public var hosts: [String]
    public var httpsCredentialRef: String?
    public var isDefault: Bool

    public init(id: String, displayName: String, gitUserName: String, gitUserEmail: String, sshKeyPath: String, hosts: [String], httpsCredentialRef: String?, isDefault: Bool) throws {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GitAccountSwitcherError.emptyDisplayName }
        guard !gitUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GitAccountSwitcherError.emptyGitUserName }
        guard !gitUserEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GitAccountSwitcherError.emptyGitUserEmail }
        guard !sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GitAccountSwitcherError.emptySSHKeyPath }
        guard hosts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw GitAccountSwitcherError.emptyHost }
        self.id = id
        self.displayName = displayName
        self.gitUserName = gitUserName
        self.gitUserEmail = gitUserEmail
        self.sshKeyPath = sshKeyPath
        self.hosts = hosts
        self.httpsCredentialRef = httpsCredentialRef
        self.isDefault = isDefault
    }
}
```

Create a minimal `@main` app that opens a `MenuBarExtra` and a basic settings window with profile and diagnostics sections.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelsTests`

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add Package.swift README.md Sources Tests
git commit -m "feat: add Swift package skeleton"
```

### Task 2: Profile Store Without Secrets

**Files:**
- Modify: `Sources/GitAccountSwitcherCore/Models.swift`
- Create: `Sources/GitAccountSwitcherCore/ProfileStore.swift`
- Create: `Tests/GitAccountSwitcherCoreTests/ProfileStoreTests.swift`

- [ ] **Step 1: Write failing persistence tests**

Test that profiles and rules round-trip through JSON, and that a fake token value is not present in the saved file because only `httpsCredentialRef` is persisted.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProfileStoreTests`

Expected: FAIL because `ProfileStore` and `FolderRule` do not exist.

- [ ] **Step 3: Implement `FolderRule`, `ProfileStoreData`, and `ProfileStore`**

Use `JSONEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]`. Store only profile metadata and credential references. Do not include secret payload properties in any Codable model.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProfileStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/GitAccountSwitcherCore/Models.swift Sources/GitAccountSwitcherCore/ProfileStore.swift Tests/GitAccountSwitcherCoreTests/ProfileStoreTests.swift
git commit -m "feat: add secret-free profile store"
```

### Task 3: Git Config Generation

**Files:**
- Create: `Sources/GitAccountSwitcherCore/GitConfigGenerator.swift`
- Create: `Tests/GitAccountSwitcherCoreTests/GitConfigGeneratorTests.swift`

- [ ] **Step 1: Write failing config generation tests**

Test that profile config contains `[user]`, `name`, `email`, and `core.sshCommand`; test that global include order writes `global.gitconfig` before `rules.gitconfig`; test folder-tree rules end with `/**`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GitConfigGeneratorTests`

Expected: FAIL because `GitConfigGenerator` does not exist.

- [ ] **Step 3: Implement deterministic Git config generation**

Implement pure functions:

- `profileConfig(for:) -> String`
- `rootIncludeConfig(paths:) -> String`
- `rulesConfig(rules:profilesDirectory:) -> String`

Escape backslashes and quotes in values. Do not shell out.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GitConfigGeneratorTests`

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/GitAccountSwitcherCore/GitConfigGenerator.swift Tests/GitAccountSwitcherCoreTests/GitConfigGeneratorTests.swift
git commit -m "feat: generate managed git config"
```

### Task 4: SSH Config Generation

**Files:**
- Create: `Sources/GitAccountSwitcherCore/SSHConfigGenerator.swift`
- Create: `Tests/GitAccountSwitcherCoreTests/SSHConfigGeneratorTests.swift`

- [ ] **Step 1: Write failing SSH generation tests**

Test that SSH config includes one host block per unique host/profile pair, `IdentitiesOnly yes`, and the expected `IdentityFile`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SSHConfigGeneratorTests`

Expected: FAIL because `SSHConfigGenerator` does not exist.

- [ ] **Step 3: Implement deterministic SSH config generation**

Generate a managed file with comments naming the owning profile. Do not modify `~/.ssh/config` here; this task only returns content.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SSHConfigGeneratorTests`

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/GitAccountSwitcherCore/SSHConfigGenerator.swift Tests/GitAccountSwitcherCoreTests/SSHConfigGeneratorTests.swift
git commit -m "feat: generate managed ssh config"
```

### Task 5: Backup-Aware Safe File Writer

**Files:**
- Create: `Sources/GitAccountSwitcherCore/SafeFileWriter.swift`
- Create: `Tests/GitAccountSwitcherCoreTests/SafeFileWriterTests.swift`

- [ ] **Step 1: Write failing safe write tests**

Test that writes outside allowed roots throw, writes create parent directories, existing files are backed up before replacement, and atomic replacement writes the final content.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SafeFileWriterTests`

Expected: FAIL because `SafeFileWriter` does not exist.

- [ ] **Step 3: Implement `SafeFileWriter`**

Use explicit allowed roots injected through `ManagedPaths`. Default app paths must be managed config directories only. Backup filenames include timestamp and original basename.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SafeFileWriterTests`

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/GitAccountSwitcherCore/SafeFileWriter.swift Tests/GitAccountSwitcherCoreTests/SafeFileWriterTests.swift
git commit -m "feat: add constrained file writer"
```

### Task 6: Diagnostics With Injectable Runner

**Files:**
- Create: `Sources/GitAccountSwitcherCore/DiagnosticsService.swift`
- Create: `Tests/GitAccountSwitcherCoreTests/DiagnosticsServiceTests.swift`

- [ ] **Step 1: Write failing diagnostics tests**

Test that diagnostics call only local `git config --show-origin` commands for `user.name`, `user.email`, and `core.sshCommand`; test command failure returns a warning instead of crashing.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DiagnosticsServiceTests`

Expected: FAIL because `DiagnosticsService` does not exist.

- [ ] **Step 3: Implement diagnostics**

Create `CommandRunning` protocol and a `ProcessCommandRunner`. Diagnostics must not run SSH network tests automatically. Add a separate method name for manual SSH tests but do not call it from automatic diagnostics.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DiagnosticsServiceTests`

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/GitAccountSwitcherCore/DiagnosticsService.swift Tests/GitAccountSwitcherCoreTests/DiagnosticsServiceTests.swift
git commit -m "feat: add local diagnostics service"
```

### Task 7: Keychain Store Boundary

**Files:**
- Create: `Sources/GitAccountSwitcherCore/KeychainStore.swift`
- Create: `Tests/GitAccountSwitcherCoreTests/KeychainStoreTests.swift`

- [ ] **Step 1: Write failing Keychain boundary tests**

Test that credential identifiers are namespaced as `git-account-switcher.<profile-id>.<purpose>` and that deleting a credential uses the same identifier.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter KeychainStoreTests`

Expected: FAIL because `KeychainStore` does not exist.

- [ ] **Step 3: Implement Keychain wrapper**

Wrap Security framework calls behind `KeychainStoring`. Keep identifier construction pure and tested. Do not write real Keychain entries in unit tests; use an in-memory fake for behavior tests.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter KeychainStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/GitAccountSwitcherCore/KeychainStore.swift Tests/GitAccountSwitcherCoreTests/KeychainStoreTests.swift
git commit -m "feat: add keychain storage boundary"
```

### Task 8: Menu Bar UI Wiring

**Files:**
- Modify: `Sources/GitAccountSwitcherApp/GitAccountSwitcherApp.swift`
- Create: `Sources/GitAccountSwitcherApp/AppViewModel.swift`

- [ ] **Step 1: Write build-focused UI code**

Create a simple menu bar UI showing active profile, profile list, diagnostics entry, settings entry, and quit. Use `MenuBarExtra`, `Settings`, and `@StateObject AppViewModel`.

- [ ] **Step 2: Build app**

Run: `swift build`

Expected: PASS.

- [ ] **Step 3: Commit**

Run:

```bash
git add Sources/GitAccountSwitcherApp
git commit -m "feat: add macos menu bar app"
```

### Task 9: Documentation and Full Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document local-only safety behavior**

Include build/test commands, managed files, backup behavior, and privacy guarantee: no telemetry and no automatic network calls.

- [ ] **Step 2: Run full test suite**

Run: `swift test`

Expected: PASS.

- [ ] **Step 3: Run full build**

Run: `swift build`

Expected: PASS.

- [ ] **Step 4: Commit**

Run:

```bash
git add README.md
git commit -m "docs: document safety model"
```
