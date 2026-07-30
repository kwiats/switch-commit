# Access Method Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit SSH/HTTPS access methods to Git profiles so HTTPS and GitHub CLI users are represented without fake SSH configuration.

**Architecture:** Add `GitAccessMethod` to the core profile and detection models, with backward-compatible decoding for existing profile JSON. Discovery records SSH/HTTPS as access signals while keeping GitHub CLI as a source hint. Git config generation, app status, and settings UI branch on the selected access method.

**Tech Stack:** Swift 6.2 package, SwiftUI/AppKit menu bar app, custom `GitAccountSwitcherCoreTestRunner`.

---

## File Structure

- Modify `Sources/GitAccountSwitcherCore/Models.swift`
  Add `GitAccessMethod`, persist it on `GitProfile`, and make SSH key validation conditional.
- Modify `Sources/GitAccountSwitcherCore/GitAccountDiscoveryModels.swift`
  Add `accessMethods` to detection signals and detected candidates.
- Modify `Sources/GitAccountSwitcherCore/GitHubCLIHostsParser.swift`
  Parse `git_protocol` as an access method signal.
- Modify `Sources/GitAccountSwitcherCore/GitRemoteParser.swift`
  Preserve whether a GitHub remote is SSH or HTTPS.
- Modify `Sources/GitAccountSwitcherCore/DetectedAccountMerger.swift`
  Merge access methods, warn on conflicts, and choose stable imported defaults.
- Modify `Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift`
  Create, import, and update profiles with explicit access methods.
- Modify `Sources/GitAccountSwitcherCore/GitConfigGenerator.swift`
  Emit `core.sshCommand` only for SSH profiles.
- Modify `Sources/GitAccountSwitcherAppLogic/AppViewModel.swift`
  Add access method updates and make connection testing SSH-only.
- Modify `Sources/GitAccountSwitcherApp/SettingsView.swift`
  Add an access picker and conditionally show SSH controls.
- Modify `Sources/GitAccountSwitcherCoreTestRunner/main.swift`
  Add focused tests for each behavior before implementation.
- Modify `README.md` and `docs/release-notes/v0.1.1.md`
  Document SSH/HTTPS profile access behavior.

## Task 1: Profile Access Model

**Files:**
- Modify: `Sources/GitAccountSwitcherCore/Models.swift`
- Test: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing profile model tests**

Add tests near the existing profile validation tests:

```swift
("profile defaults decoded access method to ssh for existing data", {
    let json = """
    {
      "profiles": [
        {
          "id": "personal",
          "displayName": "Personal",
          "gitUserName": "Personal User",
          "gitUserEmail": "me@example.com",
          "sshKeyPath": "~/.ssh/id_ed25519",
          "hosts": ["github.com"],
          "httpsCredentialRef": null,
          "isDefault": true
        }
      ],
      "rules": []
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(ProfileStoreData.self, from: json)

    try expect(decoded.profiles[0].accessMethod == .ssh, "missing access method should decode as ssh")
}),
("https profile allows empty ssh key path", {
    let profile = try GitProfile(
        id: "personal-https",
        displayName: "Personal HTTPS",
        gitUserName: "Personal User",
        gitUserEmail: "me@example.com",
        accessMethod: .https,
        sshKeyPath: "",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )

    try expect(profile.accessMethod == .https, "profile should store https access method")
    try expect(profile.sshKeyPath == "", "https profile should allow empty ssh key path")
}),
("ssh profile still rejects empty ssh key path", {
    try expectThrows(GitAccountSwitcherError.emptySSHKeyPath, {
        _ = try GitProfile(
            id: "personal-ssh",
            displayName: "Personal SSH",
            gitUserName: "Personal User",
            gitUserEmail: "me@example.com",
            accessMethod: .ssh,
            sshKeyPath: "",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
    }, "ssh profiles should require an ssh key path")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: FAIL because `GitAccessMethod` and the new `GitProfile` initializer parameter do not exist.

- [ ] **Step 3: Implement minimal model changes**

In `Models.swift`, add:

```swift
public enum GitAccessMethod: String, Codable, Equatable, Sendable {
    case ssh
    case https
}
```

Add `public var accessMethod: GitAccessMethod` to `GitProfile`, add `case accessMethod` to `CodingKeys`, and update the initializer signature:

```swift
public init(
    id: String,
    displayName: String,
    gitUserName: String,
    gitUserEmail: String,
    accessMethod: GitAccessMethod = .ssh,
    sshKeyPath: String,
    hosts: [String],
    httpsCredentialRef: String?,
    isDefault: Bool
) throws
```

Change SSH validation to:

```swift
if accessMethod == .ssh {
    guard !sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw GitAccountSwitcherError.emptySSHKeyPath
    }
}
```

Include `accessMethod` in assignment and decode it with fallback:

```swift
accessMethod: try container.decodeIfPresent(GitAccessMethod.self, forKey: .accessMethod) ?? .ssh,
```

- [ ] **Step 4: Update existing compile sites**

Add `accessMethod: .ssh` to existing `GitProfile(...)` calls where explicitness improves readability. Leave calls relying on the default only if the surrounding test is not about access methods.

- [ ] **Step 5: Run tests to verify pass**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/GitAccountSwitcherCore/Models.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: add profile access method"
```

## Task 2: Git Config Generation

**Files:**
- Modify: `Sources/GitAccountSwitcherCore/GitConfigGenerator.swift`
- Test: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing Git config test**

Add near Git config generator tests:

```swift
("git config generator omits ssh command for https profiles", {
    let profile = try GitProfile(
        id: "personal-https",
        displayName: "Personal HTTPS",
        gitUserName: "Personal User",
        gitUserEmail: "me@example.com",
        accessMethod: .https,
        sshKeyPath: "",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )

    let config = GitConfigGenerator().profileConfig(for: profile)

    try expect(config.contains("[user]"), "https profile config should include user section")
    try expect(config.contains("name = Personal User"), "https profile config should include git name")
    try expect(config.contains("email = me@example.com"), "https profile config should include git email")
    try expect(!config.contains("[core]"), "https profile config should not include core section")
    try expect(!config.contains("sshCommand"), "https profile config should not include ssh command")
})
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: FAIL because HTTPS profile config still includes `sshCommand`.

- [ ] **Step 3: Implement conditional config generation**

In `GitConfigGenerator.profileConfig(for:)`, build the user section first and append the SSH section only for `.ssh`:

```swift
let userConfig = """
[user]
    name = \(escape(profile.gitUserName))
    email = \(escape(profile.gitUserEmail))

"""

guard profile.accessMethod == .ssh else {
    return userConfig
}

return userConfig + """
[core]
    sshCommand = ssh -i \(shellQuote(profile.sshKeyPath)) -F ~/.ssh/config

"""
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/GitAccountSwitcherCore/GitConfigGenerator.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: generate git config by access method"
```

## Task 3: Detection Access Signals

**Files:**
- Modify: `Sources/GitAccountSwitcherCore/GitAccountDiscoveryModels.swift`
- Modify: `Sources/GitAccountSwitcherCore/GitHubCLIHostsParser.swift`
- Modify: `Sources/GitAccountSwitcherCore/GitRemoteParser.swift`
- Test: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing parser tests**

Update the existing GitHub CLI hosts parser test YAML to include `git_protocol: ssh` and assert:

```swift
try expect(signals[0].accessMethods == [.ssh], "gh ssh protocol should suggest ssh access")
```

Add a second parser assertion:

```swift
("github cli hosts parser extracts https protocol as access method", {
    let yaml = """
    github.com:
        oauth_token: super-secret-token
        user: pawelkwiatkowski
        git_protocol: https
    """

    let signals = GitHubCLIHostsParser().signals(from: yaml)

    try expect(signals.count == 1, "parser should emit one signal")
    try expect(signals[0].accessMethods == [.https], "gh https protocol should suggest https access")
})
```

Update the remote parser test:

```swift
let sshSignal = parser.signal(from: "git@github.com:pawelkwiatkowski/project.git")
let httpsSignal = parser.signal(from: "https://github.com/pawelkwiatkowski/project.git")

try expect(sshSignal?.accessMethods == [.ssh], "ssh remote should suggest ssh access")
try expect(httpsSignal?.accessMethods == [.https], "https remote should suggest https access")
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: FAIL because detection models have no `accessMethods`.

- [ ] **Step 3: Add access method fields**

In `DetectionSignal`, add:

```swift
public var accessMethods: [GitAccessMethod]
```

Add initializer parameter:

```swift
accessMethods: [GitAccessMethod] = [],
```

Assign:

```swift
self.accessMethods = accessMethods
```

In `DetectedGitAccount`, add the same stored property and initializer parameter.

- [ ] **Step 4: Parse GitHub CLI protocol**

In `GitHubCLIHostsParser`, track `git_protocol` while inside `github.com`. Map only exact values:

```swift
private func accessMethod(from protocolValue: String?) -> GitAccessMethod? {
    switch protocolValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "ssh":
        return .ssh
    case "https":
        return .https
    default:
        return nil
    }
}
```

When emitting the signal, pass:

```swift
accessMethods: accessMethod.map { [$0] } ?? []
```

- [ ] **Step 5: Parse remote access method**

In `GitRemoteParser`, add a private helper that returns both remote and method:

```swift
private func parsedGitHubRemote(from remoteURL: String) -> (remote: GitHubRemoteAccount, accessMethod: GitAccessMethod)? {
    let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("git@github.com:") {
        return parsePath(String(trimmed.dropFirst("git@github.com:".count))).map { ($0, .ssh) }
    }
    if trimmed.hasPrefix("https://github.com/") {
        return parsePath(String(trimmed.dropFirst("https://github.com/".count))).map { ($0, .https) }
    }
    if trimmed.hasPrefix("ssh://git@github.com/") {
        return parsePath(String(trimmed.dropFirst("ssh://git@github.com/".count))).map { ($0, .ssh) }
    }
    return nil
}
```

Make `githubRemote(from:)` return `parsedGitHubRemote(from:)?.remote`, and make `signal(from:)` pass `accessMethods: [parsed.accessMethod]`.

- [ ] **Step 6: Run tests to verify pass**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/GitAccountSwitcherCore/GitAccountDiscoveryModels.swift Sources/GitAccountSwitcherCore/GitHubCLIHostsParser.swift Sources/GitAccountSwitcherCore/GitRemoteParser.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: detect github access methods"
```

## Task 4: Merge And Import Access Methods

**Files:**
- Modify: `Sources/GitAccountSwitcherCore/DetectedAccountMerger.swift`
- Modify: `Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift`
- Modify: `Sources/GitAccountSwitcherAppLogic/AppViewModel.swift`
- Test: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing merger tests**

Add near detected account merger tests:

```swift
("detected account merger combines access methods and warns on conflict", {
    let signals = [
        DetectionSignal(provider: .github, username: "pawel", accessMethods: [.ssh], confidence: .high, source: .githubCliHostsFile),
        DetectionSignal(provider: .github, username: "pawel", accessMethods: [.https], confidence: .medium, source: .repositoryRemote)
    ]

    let account = DetectedAccountMerger().merge(signals: signals, existingProfiles: []).first

    try expect(account?.accessMethods == [.ssh, .https], "merged account should preserve stable access method order")
    try expect(account?.warnings.contains("Local data points to both SSH and HTTPS access. Choose the method before import.") == true, "conflicting access methods should warn")
})
```

Add import tests:

```swift
("profile settings import keeps https access without synthetic ssh key", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: temporaryDirectory.appendingPathComponent("profiles.json")),
        keychainStore: InMemoryKeychainStore(),
        seedProfiles: []
    )
    let account = DetectedGitAccount(
        id: "github-pawel",
        provider: .github,
        username: "pawel",
        gitUserName: "Pawel",
        gitUserEmail: "pawel@example.com",
        sshKeyPath: nil,
        hosts: ["github.com"],
        accessMethods: [.https],
        confidence: .high,
        sources: [.githubCliHostsFile],
        warnings: []
    )

    try manager.importDetectedAccount(account)

    try expect(manager.profiles[0].accessMethod == .https, "imported profile should use https")
    try expect(manager.profiles[0].sshKeyPath == "", "https import should not synthesize ssh key")
})
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: FAIL because access methods are not merged or imported.

- [ ] **Step 3: Merge access methods**

In `DetectedAccountMerger`, collect methods in stable order:

```swift
private func mergedAccessMethods(from signals: [DetectionSignal]) -> [GitAccessMethod] {
    var methods: [GitAccessMethod] = []
    for signal in signals {
        for method in signal.accessMethods where !methods.contains(method) {
            methods.append(method)
        }
    }
    return methods
}
```

Append the warning when both methods are present:

```swift
if candidate.accessMethods.contains(.ssh), candidate.accessMethods.contains(.https) {
    candidate.warnings.append("Local data points to both SSH and HTTPS access. Choose the method before import.")
}
```

- [ ] **Step 4: Import selected default access method**

In `ProfileSettingsManager.importDetectedAccount`, choose:

```swift
let accessMethod: GitAccessMethod
if account.accessMethods.contains(.ssh), account.sshKeyPath != nil {
    accessMethod = .ssh
} else if account.accessMethods.contains(.https) {
    accessMethod = .https
} else {
    accessMethod = account.sshKeyPath == nil ? .https : .ssh
}
let sshKeyPath = accessMethod == .ssh ? (account.sshKeyPath ?? "~/.ssh/id_ed25519") : ""
```

Pass `accessMethod` into `GitProfile`.

- [ ] **Step 5: Add selected profile access update**

In `ProfileSettingsManager`, add:

```swift
public func updateSelectedProfileAccessMethod(_ accessMethod: GitAccessMethod) throws {
    try updateSelectedProfile { profile in
        profile.accessMethod = accessMethod
        if accessMethod == .https {
            profile.sshKeyPath = ""
        } else if profile.sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.sshKeyPath = "~/.ssh/id_ed25519"
        }
    }
}
```

In `AppViewModel`, add a wrapper:

```swift
public func updateSelectedProfileAccessMethod(_ accessMethod: GitAccessMethod) {
    performSettingsUpdate {
        try profileSettingsManager.updateSelectedProfileAccessMethod(accessMethod)
    }
}
```

- [ ] **Step 6: Run tests to verify pass**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/GitAccountSwitcherCore/DetectedAccountMerger.swift Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift Sources/GitAccountSwitcherAppLogic/AppViewModel.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: import detected access methods"
```

## Task 5: App Status And Settings UI

**Files:**
- Modify: `Sources/GitAccountSwitcherAppLogic/AppViewModel.swift`
- Modify: `Sources/GitAccountSwitcherApp/SettingsView.swift`
- Test: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing app logic tests**

Add near existing app view model status tests:

```swift
("https profile reports neutral credential status", {
    let profile = try GitProfile(
        id: "personal-https",
        displayName: "Personal HTTPS",
        gitUserName: "Personal User",
        gitUserEmail: "me@example.com",
        accessMethod: .https,
        sshKeyPath: "",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let viewModel = try AppViewModel(seedProfiles: [profile])

    let status = viewModel.connectionStatus(for: profile)

    try expect(status.message == "Uses HTTPS credentials.", "https status should not ask for ssh")
    try expect(status.displayColorName == "green", "https profile should be locally complete")
})
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift run GitAccountSwitcherCoreTestRunner`

Expected: FAIL because HTTPS status still checks SSH key and connection results.

- [ ] **Step 3: Make status and tests SSH-only**

At the start of `AppViewModel.connectionStatus(for:)`, after host validation, add:

```swift
guard profile.accessMethod == .ssh else {
    return .connected(message: "Uses HTTPS credentials.")
}
```

At the start of `testConnectionForSelectedProfile()`, after selected profile lookup, add:

```swift
guard profile.accessMethod == .ssh else {
    settingsMessage = "HTTPS access uses Git credentials."
    connectionTestResultsByProfileId[profile.id] = []
    menuContentRevision += 1
    return
}
```

- [ ] **Step 4: Add access picker to settings**

In `SettingsView.accountForm`, add a `GridRow` before `SSH key`:

```swift
GridRow {
    Text("Access")
        .foregroundStyle(.secondary)
    Picker("Access", selection: Binding(
        get: { viewModel.selectedProfile?.accessMethod ?? .ssh },
        set: { viewModel.updateSelectedProfileAccessMethod($0) }
    )) {
        Text("SSH").tag(GitAccessMethod.ssh)
        Text("HTTPS").tag(GitAccessMethod.https)
    }
    .labelsHidden()
    .pickerStyle(.segmented)
}
```

Wrap the existing `SSH key` row in:

```swift
if viewModel.selectedProfile?.accessMethod != .https {
    GridRow {
        Text("SSH key")
            .foregroundStyle(.secondary)
        TextField("SSH key", text: Binding(
            get: { viewModel.selectedProfile?.sshKeyPath ?? "" },
            set: { viewModel.updateSelectedProfileSSHKeyPath($0) }
        ))
    }
}
```

Disable `Test Connection` in the header for HTTPS:

```swift
.disabled(profile.accessMethod == .https)
.help(profile.accessMethod == .https ? "HTTPS access uses Git credentials" : "Test SSH connection")
```

- [ ] **Step 5: Show detected access metadata**

In `detectedAccountRow`, add:

```swift
metadataLabel("Access: \(accessMethodsText(account.accessMethods))", systemImage: "key")
```

Add helper:

```swift
private func accessMethodsText(_ methods: [GitAccessMethod]) -> String {
    if methods.isEmpty {
        return "Choose during import"
    }
    return methods.map { method in
        switch method {
        case .ssh:
            return "SSH"
        case .https:
            return "HTTPS"
        }
    }.joined(separator: ", ")
}
```

- [ ] **Step 6: Run tests and build**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
```

Expected: both PASS.

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/GitAccountSwitcherAppLogic/AppViewModel.swift Sources/GitAccountSwitcherApp/SettingsView.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: show profile access method in settings"
```

## Task 6: Documentation And Final Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/release-notes/v0.1.1.md`

- [ ] **Step 1: Update README**

Add a short note near local GitHub discovery:

```markdown
Profiles use an explicit access method: SSH or HTTPS. SSH profiles generate a managed `core.sshCommand` and can run a manual SSH connection test. HTTPS profiles rely on local Git credentials or GitHub CLI-configured credentials and do not require an SSH key.
```

- [ ] **Step 2: Update release notes**

Add:

```markdown
- Added explicit SSH/HTTPS access methods for profiles so HTTPS and GitHub CLI credential users are not forced into SSH key configuration.
```

- [ ] **Step 3: Run final verification**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
swift build
```

Expected: both PASS.

- [ ] **Step 4: Review diff**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only intended files changed.

- [ ] **Step 5: Commit docs**

Run:

```bash
git add README.md docs/release-notes/v0.1.1.md docs/superpowers/plans/2026-07-30-access-method-profiles-implementation.md
git commit -m "docs: document profile access methods"
```

- [ ] **Step 6: Push and open draft PR**

Run:

```bash
git push -u origin codex/access-method-profiles
gh pr create --draft --title "Add explicit SSH and HTTPS access methods" --body-file docs/pull-request-description.md
```

Expected: branch pushed and draft pull request opened. If `gh` is not authenticated, report the exact failure and leave the branch ready to push.
