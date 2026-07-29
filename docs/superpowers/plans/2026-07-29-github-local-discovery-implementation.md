# GitHub Local Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-only GitHub account discovery flow that suggests GitHub accounts from local Git, SSH, GitHub CLI, and user-approved repository folder signals.

**Architecture:** Add pure discovery models, parsers, signal merging, and a read-only discovery service to `GitAccountSwitcherCore`; expose discovered candidates through `AppViewModel`; show and import candidates from `SettingsView`. Discovery never writes profiles, Git config, SSH config, Keychain data, or performs network/API checks until the user explicitly imports a candidate as a normal profile.

**Tech Stack:** Swift 6.2, Swift Package Manager, SwiftUI, Foundation, existing `CommandRunning`, existing `GitAccountSwitcherCoreTestRunner`.

---

## File Structure

- Create: `Sources/GitAccountSwitcherCore/GitAccountDiscoveryModels.swift`
  Defines provider, confidence, source, signal, remote account, and detected account types.
- Create: `Sources/GitAccountSwitcherCore/GitHubCLIHostsParser.swift`
  Parses the small subset of `gh hosts.yml` needed for local username discovery while ignoring token values.
- Create: `Sources/GitAccountSwitcherCore/GitRemoteParser.swift`
  Parses GitHub SSH, HTTPS, and `ssh://` remote URLs into provider/owner/repository metadata.
- Create: `Sources/GitAccountSwitcherCore/DetectedAccountMerger.swift`
  Combines discovery signals, assigns confidence, emits warnings, and deduplicates candidates against existing profiles.
- Create: `Sources/GitAccountSwitcherCore/GitHubLocalDiscoveryService.swift`
  Orchestrates local file reads, allowlisted local commands, SSH config checks, and manual folder scanning.
- Modify: `Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift`
  Adds import from a detected candidate into a validated `GitProfile`.
- Modify: `Sources/GitAccountSwitcherAppLogic/AppViewModel.swift`
  Stores detected accounts, exposes refresh/import/scan methods, and keeps UI messages user-safe.
- Modify: `Sources/GitAccountSwitcherApp/SettingsView.swift`
  Adds a compact `Detected Accounts` section and manual scan action.
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`
  Adds focused tests for parsing, merging, service command allowlist, no-secret persistence, import, view model, and UI-facing state.
- Modify: `README.md`
  Documents local-only GitHub discovery and the user-approved folder scan.
- Modify: `docs/release-notes/v0.1.0.md`
  Adds a short note about GitHub local discovery.

---

### Task 1: Discovery Models

**Files:**
- Create: `Sources/GitAccountSwitcherCore/GitAccountDiscoveryModels.swift`
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing model tests**

Add this test case near the other model tests in `Sources/GitAccountSwitcherCoreTestRunner/main.swift`:

```swift
("detected git account exposes stable local-only metadata", {
    let account = DetectedGitAccount(
        id: "github-pawelkwiatkowski",
        provider: .github,
        username: "pawelkwiatkowski",
        gitUserName: "Pawel Kwiatkowski",
        gitUserEmail: "pawel@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        confidence: .high,
        sources: [.githubCliHostsFile, .globalGitConfig],
        warnings: []
    )

    try expect(account.id == "github-pawelkwiatkowski", "detected account id should be stable")
    try expect(account.provider == .github, "provider should be github")
    try expect(account.confidence == .high, "confidence should be high")
    try expect(account.sources.contains(.githubCliHostsFile), "sources should include gh hosts file")
    try expect(account.hosts == ["github.com"], "hosts should contain github.com")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: build fails because `DetectedGitAccount`, `GitAccountProvider`, `DetectionConfidence`, and `DetectionSource` do not exist.

- [ ] **Step 3: Add discovery model types**

Create `Sources/GitAccountSwitcherCore/GitAccountDiscoveryModels.swift`:

```swift
import Foundation

public enum GitAccountProvider: String, Codable, Hashable, Sendable {
    case github
}

public enum DetectionConfidence: String, Codable, Hashable, Comparable, Sendable {
    case low
    case medium
    case high

    public static func < (lhs: DetectionConfidence, rhs: DetectionConfidence) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .low:
            return 0
        case .medium:
            return 1
        case .high:
            return 2
        }
    }
}

public enum DetectionSource: String, Codable, Hashable, Sendable {
    case githubCliHostsFile
    case githubCliInstalled
    case globalGitConfig
    case gitCredentialUsername
    case sshConfig
    case sshResolvedConfig
    case repositoryRemote
}

public struct GitHubRemoteAccount: Equatable, Sendable {
    public var owner: String
    public var repository: String

    public init(owner: String, repository: String) {
        self.owner = owner
        self.repository = repository
    }
}

public struct DetectionSignal: Equatable, Sendable {
    public var provider: GitAccountProvider
    public var username: String?
    public var gitUserName: String?
    public var gitUserEmail: String?
    public var sshKeyPath: String?
    public var hosts: [String]
    public var confidence: DetectionConfidence
    public var source: DetectionSource
    public var warnings: [String]

    public init(
        provider: GitAccountProvider,
        username: String? = nil,
        gitUserName: String? = nil,
        gitUserEmail: String? = nil,
        sshKeyPath: String? = nil,
        hosts: [String] = ["github.com"],
        confidence: DetectionConfidence,
        source: DetectionSource,
        warnings: [String] = []
    ) {
        self.provider = provider
        self.username = username
        self.gitUserName = gitUserName
        self.gitUserEmail = gitUserEmail
        self.sshKeyPath = sshKeyPath
        self.hosts = hosts
        self.confidence = confidence
        self.source = source
        self.warnings = warnings
    }
}

public struct DetectedGitAccount: Equatable, Identifiable, Sendable {
    public var id: String
    public var provider: GitAccountProvider
    public var username: String?
    public var gitUserName: String?
    public var gitUserEmail: String?
    public var sshKeyPath: String?
    public var hosts: [String]
    public var confidence: DetectionConfidence
    public var sources: [DetectionSource]
    public var warnings: [String]

    public init(
        id: String,
        provider: GitAccountProvider,
        username: String?,
        gitUserName: String?,
        gitUserEmail: String?,
        sshKeyPath: String?,
        hosts: [String],
        confidence: DetectionConfidence,
        sources: [DetectionSource],
        warnings: [String]
    ) {
        self.id = id
        self.provider = provider
        self.username = username
        self.gitUserName = gitUserName
        self.gitUserEmail = gitUserEmail
        self.sshKeyPath = sshKeyPath
        self.hosts = hosts
        self.confidence = confidence
        self.sources = sources
        self.warnings = warnings
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitAccountSwitcherCore/GitAccountDiscoveryModels.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: add git account discovery models"
```

---

### Task 2: GitHub CLI Hosts Parser

**Files:**
- Create: `Sources/GitAccountSwitcherCore/GitHubCLIHostsParser.swift`
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing parser tests**

Add these test cases:

```swift
("github cli hosts parser extracts username and ignores token", {
    let yaml = """
    github.com:
        oauth_token: super-secret-token
        user: pawelkwiatkowski
        git_protocol: ssh
    """

    let signals = GitHubCLIHostsParser().signals(from: yaml)

    try expect(signals.count == 1, "parser should emit one signal")
    try expect(signals[0].username == "pawelkwiatkowski", "parser should extract user")
    try expect(signals[0].confidence == .high, "gh hosts username should be high confidence")
    try expect(signals[0].source == .githubCliHostsFile, "source should be gh hosts file")
    try expect(signals[0].warnings.isEmpty, "valid hosts file should not warn")
    try expect(!String(describing: signals).contains("super-secret-token"), "token should never appear in parsed output")
}),
("github cli hosts parser returns warning for github host without username", {
    let yaml = """
    github.com:
        oauth_token: super-secret-token
        git_protocol: ssh
    """

    let signals = GitHubCLIHostsParser().signals(from: yaml)

    try expect(signals.count == 1, "parser should emit one weak signal")
    try expect(signals[0].username == nil, "missing username should remain nil")
    try expect(signals[0].confidence == .medium, "configured gh host should be medium confidence")
    try expect(signals[0].warnings.contains("GitHub CLI host is configured without a visible username."), "missing username should warn")
    try expect(!String(describing: signals).contains("super-secret-token"), "token should be ignored")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: build fails because `GitHubCLIHostsParser` does not exist.

- [ ] **Step 3: Implement minimal parser**

Create `Sources/GitAccountSwitcherCore/GitHubCLIHostsParser.swift`:

```swift
import Foundation

public struct GitHubCLIHostsParser: Sendable {
    public init() {}

    public func signals(from content: String) -> [DetectionSignal] {
        let lines = content.split(whereSeparator: \.isNewline).map(String.init)
        var insideGitHub = false
        var username: String?
        var sawGitHubHost = false

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(":") && !rawLine.hasPrefix(" ") && !rawLine.hasPrefix("\t") {
                insideGitHub = trimmed == "github.com:"
                sawGitHubHost = insideGitHub || sawGitHubHost
                continue
            }

            guard insideGitHub else {
                continue
            }

            if let value = value(for: "user", in: trimmed) {
                username = value
            } else if let value = value(for: "username", in: trimmed) {
                username = value
            }
        }

        guard sawGitHubHost else {
            return []
        }

        if let username, !username.isEmpty {
            return [
                DetectionSignal(
                    provider: .github,
                    username: username,
                    confidence: .high,
                    source: .githubCliHostsFile
                )
            ]
        }

        return [
            DetectionSignal(
                provider: .github,
                confidence: .medium,
                source: .githubCliHostsFile,
                warnings: ["GitHub CLI host is configured without a visible username."]
            )
        ]
    }

    private func value(for key: String, in line: String) -> String? {
        let prefix = "\(key):"
        guard line.hasPrefix(prefix) else {
            return nil
        }
        let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitAccountSwitcherCore/GitHubCLIHostsParser.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: parse local github cli hosts"
```

---

### Task 3: GitHub Remote Parser

**Files:**
- Create: `Sources/GitAccountSwitcherCore/GitRemoteParser.swift`
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing remote parser tests**

Add this test case:

```swift
("git remote parser recognizes github ssh https and ssh url remotes", {
    let parser = GitRemoteParser()

    let scp = parser.githubRemote(from: "git@github.com:pawelkwiatkowski/project.git")
    let https = parser.githubRemote(from: "https://github.com/pawelkwiatkowski/project.git")
    let sshURL = parser.githubRemote(from: "ssh://git@github.com/pawelkwiatkowski/project.git")
    let nonGitHub = parser.githubRemote(from: "git@gitlab.com:pawelkwiatkowski/project.git")

    try expect(scp == GitHubRemoteAccount(owner: "pawelkwiatkowski", repository: "project"), "scp-like ssh remote should parse")
    try expect(https == GitHubRemoteAccount(owner: "pawelkwiatkowski", repository: "project"), "https remote should parse")
    try expect(sshURL == GitHubRemoteAccount(owner: "pawelkwiatkowski", repository: "project"), "ssh url remote should parse")
    try expect(nonGitHub == nil, "non-github remote should not parse")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: build fails because `GitRemoteParser` does not exist.

- [ ] **Step 3: Implement remote parser**

Create `Sources/GitAccountSwitcherCore/GitRemoteParser.swift`:

```swift
import Foundation

public struct GitRemoteParser: Sendable {
    public init() {}

    public func githubRemote(from remoteURL: String) -> GitHubRemoteAccount? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("git@github.com:") {
            return parsePath(String(trimmed.dropFirst("git@github.com:".count)))
        }
        if trimmed.hasPrefix("https://github.com/") {
            return parsePath(String(trimmed.dropFirst("https://github.com/".count)))
        }
        if trimmed.hasPrefix("ssh://git@github.com/") {
            return parsePath(String(trimmed.dropFirst("ssh://git@github.com/".count)))
        }
        return nil
    }

    public func signal(from remoteURL: String) -> DetectionSignal? {
        guard let remote = githubRemote(from: remoteURL) else {
            return nil
        }
        return DetectionSignal(
            provider: .github,
            username: nil,
            hosts: ["github.com"],
            confidence: .medium,
            source: .repositoryRemote,
            warnings: ["Remote owner '\(remote.owner)' may be a user or an organization."]
        )
    }

    private func parsePath(_ path: String) -> GitHubRemoteAccount? {
        let cleaned = path.hasSuffix(".git") ? String(path.dropLast(4)) : path
        let parts = cleaned.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        return GitHubRemoteAccount(owner: parts[0], repository: parts[1])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitAccountSwitcherCore/GitRemoteParser.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: parse github remote urls"
```

---

### Task 4: Signal Merger And Dedupe

**Files:**
- Create: `Sources/GitAccountSwitcherCore/DetectedAccountMerger.swift`
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing merger tests**

Add these test cases:

```swift
("detected account merger combines github signals into one candidate", {
    let signals = [
        DetectionSignal(provider: .github, username: "pawelkwiatkowski", confidence: .high, source: .githubCliHostsFile),
        DetectionSignal(provider: .github, gitUserName: "Pawel Kwiatkowski", gitUserEmail: "pawel@example.com", confidence: .low, source: .globalGitConfig),
        DetectionSignal(provider: .github, sshKeyPath: "~/.ssh/id_ed25519", confidence: .medium, source: .sshResolvedConfig)
    ]

    let accounts = DetectedAccountMerger().merge(signals: signals, existingProfiles: [])

    try expect(accounts.count == 1, "signals should merge into one account")
    try expect(accounts[0].id == "github-pawelkwiatkowski", "username should drive stable id")
    try expect(accounts[0].displaySummary == "pawelkwiatkowski", "display summary should prefer username")
    try expect(accounts[0].gitUserEmail == "pawel@example.com", "git email should merge")
    try expect(accounts[0].sshKeyPath == "~/.ssh/id_ed25519", "ssh path should merge")
    try expect(accounts[0].confidence == .high, "highest confidence should win")
    try expect(accounts[0].sources == [.githubCliHostsFile, .globalGitConfig, .sshResolvedConfig], "sources should be stable and unique")
}),
("detected account merger skips existing github profile duplicates", {
    let existing = try GitProfile(
        id: "personal",
        displayName: "pawelkwiatkowski",
        gitUserName: "Pawel Kwiatkowski",
        gitUserEmail: "pawel@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        httpsCredentialRef: nil,
        isDefault: true
    )
    let signals = [
        DetectionSignal(provider: .github, username: "pawelkwiatkowski", gitUserEmail: "pawel@example.com", confidence: .high, source: .githubCliHostsFile)
    ]

    let accounts = DetectedAccountMerger().merge(signals: signals, existingProfiles: [existing])

    try expect(accounts.isEmpty, "duplicate existing github profile should suppress suggestion")
})
```

Also add this convenience extension inside the test runner file if needed:

```swift
extension DetectedGitAccount {
    var displaySummary: String {
        username ?? gitUserName ?? gitUserEmail ?? "GitHub Account"
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: build fails because `DetectedAccountMerger` does not exist.

- [ ] **Step 3: Implement merger**

Create `Sources/GitAccountSwitcherCore/DetectedAccountMerger.swift`:

```swift
import Foundation

public struct DetectedAccountMerger: Sendable {
    public init() {}

    public func merge(signals: [DetectionSignal], existingProfiles: [GitProfile]) -> [DetectedGitAccount] {
        let githubSignals = signals.filter { $0.provider == .github }
        guard githubSignals.contains(where: { $0.source != .globalGitConfig }) else {
            return []
        }

        var candidate = DetectedGitAccount(
            id: "github-account",
            provider: .github,
            username: nil,
            gitUserName: nil,
            gitUserEmail: nil,
            sshKeyPath: nil,
            hosts: ["github.com"],
            confidence: .low,
            sources: [],
            warnings: []
        )

        for signal in githubSignals {
            candidate.username = candidate.username ?? signal.username
            candidate.gitUserName = candidate.gitUserName ?? signal.gitUserName
            candidate.gitUserEmail = candidate.gitUserEmail ?? signal.gitUserEmail
            candidate.sshKeyPath = candidate.sshKeyPath ?? signal.sshKeyPath
            candidate.hosts = unique(candidate.hosts + signal.hosts)
            candidate.sources = unique(candidate.sources + [signal.source])
            candidate.warnings = unique(candidate.warnings + signal.warnings)
            candidate.confidence = max(candidate.confidence, signal.confidence)
        }

        candidate.id = stableId(for: candidate)
        guard !isDuplicate(candidate, existingProfiles: existingProfiles) else {
            return []
        }
        return [candidate]
    }

    private func stableId(for account: DetectedGitAccount) -> String {
        if let username = account.username, let safe = safeIdentifier("github-\(username)") {
            return safe
        }
        if let email = account.gitUserEmail, let safe = safeIdentifier("github-\(email)") {
            return safe
        }
        return "github-account"
    }

    private func safeIdentifier(_ value: String) -> String? {
        let normalized = value
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." {
                    return character
                }
                return "-"
            }
        let id = String(normalized).trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        do {
            try SecurityValidation.requireSafeIdentifier(id)
            return id
        } catch {
            return nil
        }
    }

    private func isDuplicate(_ account: DetectedGitAccount, existingProfiles: [GitProfile]) -> Bool {
        existingProfiles.contains { profile in
            let hosts = Set(profile.hosts.map { $0.lowercased() })
            guard hosts.contains("github.com") else {
                return false
            }
            if let email = account.gitUserEmail, profile.gitUserEmail.caseInsensitiveCompare(email) == .orderedSame {
                return true
            }
            if let username = account.username, profile.displayName.caseInsensitiveCompare(username) == .orderedSame {
                return true
            }
            return false
        }
    }

    private func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        var result: [T] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitAccountSwitcherCore/DetectedAccountMerger.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: merge detected github account signals"
```

---

### Task 5: Local Discovery Service

**Files:**
- Create: `Sources/GitAccountSwitcherCore/GitHubLocalDiscoveryService.swift`
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing service tests**

Add these test cases:

```swift
("github local discovery service uses only allowlisted local commands", {
    final class FakeDiscoveryRunner: CommandRunning {
        var commands: [[String]] = []

        func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
            commands.append([command] + arguments)
            if command == "git", arguments == ["config", "--global", "--get", "user.name"] {
                return CommandResult(exitCode: 0, standardOutput: "Pawel Kwiatkowski\n", standardError: "")
            }
            if command == "git", arguments == ["config", "--global", "--get", "user.email"] {
                return CommandResult(exitCode: 0, standardOutput: "pawel@example.com\n", standardError: "")
            }
            if command == "ssh", arguments == ["-G", "github.com"] {
                return CommandResult(exitCode: 0, standardOutput: "identityfile ~/.ssh/id_ed25519\n", standardError: "")
            }
            if command == "gh", arguments == ["--version"] {
                return CommandResult(exitCode: 0, standardOutput: "gh version 2.0.0\n", standardError: "")
            }
            return CommandResult(exitCode: 1, standardOutput: "", standardError: "missing")
        }
    }

    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let ghConfig = temporaryDirectory.appendingPathComponent(".config/gh", isDirectory: true)
    try FileManager.default.createDirectory(at: ghConfig, withIntermediateDirectories: true)
    try """
    github.com:
        oauth_token: secret-token
        user: pawelkwiatkowski
    """.write(to: ghConfig.appendingPathComponent("hosts.yml"), atomically: true, encoding: .utf8)

    let runner = FakeDiscoveryRunner()
    let service = GitHubLocalDiscoveryService(
        homeDirectory: temporaryDirectory,
        commandRunner: runner
    )

    let accounts = service.detect(existingProfiles: [])

    try expect(accounts.count == 1, "service should detect one github account")
    try expect(accounts[0].username == "pawelkwiatkowski", "username should come from local hosts file")
    try expect(accounts[0].gitUserEmail == "pawel@example.com", "git email should come from global config")
    try expect(accounts[0].sshKeyPath == "~/.ssh/id_ed25519", "ssh key should come from resolved ssh config")
    try expect(runner.commands.contains(["gh", "--version"]), "service may check gh installation")
    try expect(!runner.commands.contains { $0.contains("auth") || $0.contains("api") }, "service must not run gh auth or gh api")
}),
("github local discovery manual scan reads only git configs under selected folder", {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let repoGit = root.appendingPathComponent("project/.git", isDirectory: true)
    try FileManager.default.createDirectory(at: repoGit, withIntermediateDirectories: true)
    try """
    [remote "origin"]
        url = git@github.com:pawelkwiatkowski/project.git
    """.write(to: repoGit.appendingPathComponent("config"), atomically: true, encoding: .utf8)

    let service = GitHubLocalDiscoveryService(
        homeDirectory: root,
        commandRunner: ProcessCommandRunner()
    )

    let signals = service.repositoryRemoteSignals(in: root)

    try expect(signals.count == 1, "manual scan should find one github remote")
    try expect(signals[0].source == .repositoryRemote, "manual scan source should be repository remote")
    try expect(signals[0].warnings.contains("Remote owner 'pawelkwiatkowski' may be a user or an organization."), "remote owner should not be treated as certain username")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: build fails because `GitHubLocalDiscoveryService` does not exist.

- [ ] **Step 3: Implement discovery service**

Create `Sources/GitAccountSwitcherCore/GitHubLocalDiscoveryService.swift`:

```swift
import Foundation

public struct GitHubLocalDiscoveryService {
    private let homeDirectory: URL
    private let commandRunner: CommandRunning
    private let fileManager: FileManager
    private let hostsParser: GitHubCLIHostsParser
    private let remoteParser: GitRemoteParser
    private let merger: DetectedAccountMerger

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        commandRunner: CommandRunning = ProcessCommandRunner(),
        fileManager: FileManager = .default,
        hostsParser: GitHubCLIHostsParser = GitHubCLIHostsParser(),
        remoteParser: GitRemoteParser = GitRemoteParser(),
        merger: DetectedAccountMerger = DetectedAccountMerger()
    ) {
        self.homeDirectory = homeDirectory
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        self.hostsParser = hostsParser
        self.remoteParser = remoteParser
        self.merger = merger
    }

    public func detect(existingProfiles: [GitProfile]) -> [DetectedGitAccount] {
        merger.merge(signals: automaticSignals(), existingProfiles: existingProfiles)
    }

    public func detect(in folderURL: URL, existingProfiles: [GitProfile]) -> [DetectedGitAccount] {
        merger.merge(
            signals: automaticSignals() + repositoryRemoteSignals(in: folderURL),
            existingProfiles: existingProfiles
        )
    }

    public func automaticSignals() -> [DetectionSignal] {
        var signals: [DetectionSignal] = []
        signals.append(contentsOf: githubCLIHostsSignals())
        signals.append(contentsOf: globalGitConfigSignals())
        signals.append(contentsOf: githubCredentialSignals())
        signals.append(contentsOf: githubCLIInstalledSignal())
        signals.append(contentsOf: sshConfigSignals())
        signals.append(contentsOf: sshResolvedConfigSignals())
        return signals
    }

    public func repositoryRemoteSignals(in folderURL: URL) -> [DetectionSignal] {
        let root = folderURL.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        var signals: [DetectionSignal] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == ".git" else {
                continue
            }
            let configURL = url.appendingPathComponent("config")
            guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
                continue
            }
            for remoteURL in remoteURLs(fromGitConfig: content) {
                if let signal = remoteParser.signal(from: remoteURL) {
                    signals.append(signal)
                }
            }
            enumerator.skipDescendants()
        }
        return signals
    }

    private func githubCLIHostsSignals() -> [DetectionSignal] {
        let url = homeDirectory.appendingPathComponent(".config/gh/hosts.yml")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return hostsParser.signals(from: content)
    }

    private func globalGitConfigSignals() -> [DetectionSignal] {
        let name = trimmedOutput(command: "git", arguments: ["config", "--global", "--get", "user.name"])
        let email = trimmedOutput(command: "git", arguments: ["config", "--global", "--get", "user.email"])
        guard name != nil || email != nil else {
            return []
        }
        return [
            DetectionSignal(
                provider: .github,
                gitUserName: name,
                gitUserEmail: email,
                confidence: .low,
                source: .globalGitConfig
            )
        ]
    }

    private func githubCredentialSignals() -> [DetectionSignal] {
        let keys = [
            "credential.https://github.com.username",
            "credential.github.com.username"
        ]
        return keys.compactMap { key in
            guard let username = trimmedOutput(command: "git", arguments: ["config", "--global", "--get", key]) else {
                return nil
            }
            return DetectionSignal(
                provider: .github,
                username: username,
                confidence: .high,
                source: .gitCredentialUsername
            )
        }
    }

    private func githubCLIInstalledSignal() -> [DetectionSignal] {
        guard trimmedOutput(command: "gh", arguments: ["--version"]) != nil else {
            return []
        }
        return [
            DetectionSignal(
                provider: .github,
                confidence: .medium,
                source: .githubCliInstalled
            )
        ]
    }

    private func sshConfigSignals() -> [DetectionSignal] {
        let urls = [
            homeDirectory.appendingPathComponent(".ssh/config"),
            homeDirectory.appendingPathComponent(".ssh/git-account-switcher.conf")
        ]
        return urls.compactMap { url in
            guard let content = try? String(contentsOf: url, encoding: .utf8),
                  content.localizedCaseInsensitiveContains("github.com") else {
                return nil
            }
            return DetectionSignal(
                provider: .github,
                confidence: .medium,
                source: .sshConfig
            )
        }
    }

    private func sshResolvedConfigSignals() -> [DetectionSignal] {
        guard let output = trimmedOutput(command: "ssh", arguments: ["-G", "github.com"]) else {
            return []
        }
        let identity = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0.lowercased().hasPrefix("identityfile ") }
            .map { String($0.dropFirst("identityfile ".count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return [
            DetectionSignal(
                provider: .github,
                sshKeyPath: identity,
                confidence: .medium,
                source: .sshResolvedConfig
            )
        ]
    }

    private func trimmedOutput(command: String, arguments: [String]) -> String? {
        do {
            let result = try commandRunner.run(command, arguments: arguments, workingDirectory: nil)
            guard result.exitCode == 0 else {
                return nil
            }
            let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? nil : output
        } catch {
            return nil
        }
    }

    private func remoteURLs(fromGitConfig content: String) -> [String] {
        content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { line in
                guard line.hasPrefix("url =") else {
                    return nil
                }
                return String(line.dropFirst("url =".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitAccountSwitcherCore/GitHubLocalDiscoveryService.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: discover local github accounts"
```

---

### Task 6: Import Candidate Into Profile Settings

**Files:**
- Modify: `Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift`
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing import tests**

Add these test cases:

```swift
("profile settings manager imports complete detected github account", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        seedProfiles: []
    )
    let account = DetectedGitAccount(
        id: "github-pawelkwiatkowski",
        provider: .github,
        username: "pawelkwiatkowski",
        gitUserName: "Pawel Kwiatkowski",
        gitUserEmail: "pawel@example.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        confidence: .high,
        sources: [.githubCliHostsFile],
        warnings: []
    )

    try manager.importDetectedAccount(account)

    try expect(manager.profiles.count == 1, "import should create one profile")
    try expect(manager.profiles[0].id == "github-pawelkwiatkowski", "profile id should use detected id")
    try expect(manager.profiles[0].displayName == "pawelkwiatkowski", "display name should prefer username")
    try expect(manager.profiles[0].httpsCredentialRef == nil, "import must not store credential refs")
    try expect(manager.activeProfileId == "github-pawelkwiatkowski", "first imported profile should become active")
}),
("profile settings manager refuses incomplete detected github account", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let manager = try ProfileSettingsManager(
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        seedProfiles: []
    )
    let account = DetectedGitAccount(
        id: "github-account",
        provider: .github,
        username: nil,
        gitUserName: "Pawel Kwiatkowski",
        gitUserEmail: nil,
        sshKeyPath: "~/.ssh/id_ed25519",
        hosts: ["github.com"],
        confidence: .medium,
        sources: [.globalGitConfig],
        warnings: []
    )

    try expectThrows(GitAccountSwitcherError.emptyGitUserEmail, {
        try manager.importDetectedAccount(account)
    }, "incomplete detected account should not be saved as profile")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: build fails because `importDetectedAccount` does not exist.

- [ ] **Step 3: Implement import method**

Modify `Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift` by adding this public method near `addProfile()`:

```swift
public func importDetectedAccount(_ account: DetectedGitAccount) throws {
    let displayName = account.username ?? account.gitUserName ?? "GitHub Account"
    let gitUserName = account.gitUserName ?? account.username ?? ""
    let gitUserEmail = account.gitUserEmail ?? ""
    let sshKeyPath = account.sshKeyPath ?? "~/.ssh/id_ed25519"
    let hosts = account.hosts.isEmpty ? ["github.com"] : account.hosts
    let profileId = uniqueProfileId(base: account.id)

    let profile = try GitProfile(
        id: profileId,
        displayName: displayName,
        gitUserName: gitUserName,
        gitUserEmail: gitUserEmail,
        sshKeyPath: sshKeyPath,
        hosts: hosts,
        httpsCredentialRef: nil,
        isDefault: profiles.isEmpty
    )

    profiles.append(profile)
    selectedProfileId = profile.id
    if activeProfileId == nil {
        activeProfileId = profile.id
    }
    normalizeDefaultFlags()
    statusMessage = "Added detected GitHub account \(profile.displayName)."
    try persist()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitAccountSwitcherCore/ProfileSettingsManager.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: import detected github accounts"
```

---

### Task 7: App View Model Integration

**Files:**
- Modify: `Sources/GitAccountSwitcherAppLogic/AppViewModel.swift`
- Modify: `Sources/GitAccountSwitcherCoreTestRunner/main.swift`

- [ ] **Step 1: Write failing view model tests**

Add this test case:

```swift
("app view model refreshes and imports detected github accounts", {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let ghConfig = temporaryDirectory.appendingPathComponent(".config/gh", isDirectory: true)
    try FileManager.default.createDirectory(at: ghConfig, withIntermediateDirectories: true)
    try """
    github.com:
        user: pawelkwiatkowski
    """.write(to: ghConfig.appendingPathComponent("hosts.yml"), atomically: true, encoding: .utf8)

    final class FakeDiscoveryRunner: CommandRunning {
        func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
            if command == "git", arguments == ["config", "--global", "--get", "user.name"] {
                return CommandResult(exitCode: 0, standardOutput: "Pawel Kwiatkowski\n", standardError: "")
            }
            if command == "git", arguments == ["config", "--global", "--get", "user.email"] {
                return CommandResult(exitCode: 0, standardOutput: "pawel@example.com\n", standardError: "")
            }
            if command == "ssh", arguments == ["-G", "github.com"] {
                return CommandResult(exitCode: 0, standardOutput: "identityfile ~/.ssh/id_ed25519\n", standardError: "")
            }
            return CommandResult(exitCode: 1, standardOutput: "", standardError: "missing")
        }
    }

    let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
    let discovery = GitHubLocalDiscoveryService(
        homeDirectory: temporaryDirectory,
        commandRunner: FakeDiscoveryRunner()
    )
    let viewModel = AppViewModel(
        profiles: [],
        profileStore: ProfileStore(fileURL: storeURL),
        keychainStore: InMemoryKeychainStore(),
        githubDiscoveryService: discovery
    )

    viewModel.refreshDetectedAccounts()
    try expect(viewModel.detectedAccounts.count == 1, "view model should expose detected account")

    viewModel.importDetectedAccount(id: "github-pawelkwiatkowski")
    try expect(viewModel.profiles.count == 1, "import should create profile")
    try expect(viewModel.profiles[0].displayName == "pawelkwiatkowski", "profile should use detected username")
    try expect(viewModel.detectedAccounts.isEmpty, "import should refresh suggestions and remove duplicate")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: build fails because `AppViewModel` does not accept `githubDiscoveryService` and does not expose detection methods.

- [ ] **Step 3: Add view model state and methods**

Modify `Sources/GitAccountSwitcherAppLogic/AppViewModel.swift`:

Add published state and dependency:

```swift
@Published public private(set) var detectedAccounts: [DetectedGitAccount]

private let githubDiscoveryService: GitHubLocalDiscoveryService
```

Update `init` signature:

```swift
public init(
    profiles: [GitProfile]? = nil,
    activeProfileId: String? = nil,
    diagnosticsText: String = "Diagnostics have not run.",
    presentationRequest: AppPresentationRequest? = nil,
    profileStore: ProfileStore? = nil,
    keychainStore: KeychainStoring = SystemKeychainStore(),
    githubDiscoveryService: GitHubLocalDiscoveryService? = nil
)
```

Inside `init`, assign:

```swift
self.githubDiscoveryService = githubDiscoveryService ?? GitHubLocalDiscoveryService()
self.detectedAccounts = []
```

Add methods:

```swift
public func refreshDetectedAccounts() {
    detectedAccounts = githubDiscoveryService.detect(existingProfiles: profiles)
    if detectedAccounts.isEmpty {
        settingsMessage = "No local GitHub account was detected."
    } else {
        settingsMessage = "Detected \(detectedAccounts.count) local GitHub account suggestion."
    }
}

public func scanSelectedFolderForGitHubAccounts(_ folderURL: URL) {
    detectedAccounts = githubDiscoveryService.detect(in: folderURL, existingProfiles: profiles)
    if detectedAccounts.isEmpty {
        settingsMessage = "No GitHub remotes were detected in the selected folder."
    } else {
        settingsMessage = "Detected \(detectedAccounts.count) GitHub account suggestion from local data."
    }
}

public func importDetectedAccount(id: String) {
    guard let account = detectedAccounts.first(where: { $0.id == id }) else {
        return
    }
    performSettingsUpdate {
        try profileSettingsManager.importDetectedAccount(account)
    }
    detectedAccounts = githubDiscoveryService.detect(existingProfiles: profiles)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitAccountSwitcherAppLogic/AppViewModel.swift Sources/GitAccountSwitcherCoreTestRunner/main.swift
git commit -m "feat: expose github discovery in app state"
```

---

### Task 8: Settings UI

**Files:**
- Modify: `Sources/GitAccountSwitcherApp/SettingsView.swift`

- [ ] **Step 1: Add manual inspection checklist before UI changes**

Before editing, note the current settings layout:

```text
Left sidebar: profile list and active profile footer.
Right pane: selected profile detail form, status message, diagnostics text.
New GitHub discovery UI should live in the right pane above the diagnostics footer to avoid crowding the profile list.
```

- [ ] **Step 2: Add detected accounts section**

Modify `accountDetail` so the profile detail includes `detectedAccountsSection` before `footer`:

```swift
private var accountDetail: some View {
    VStack(alignment: .leading, spacing: 16) {
        if let profile = viewModel.selectedProfile {
            header(for: profile)
            accountForm
            detectedAccountsSection
            Spacer()
            footer
        } else {
            emptyState
        }
    }
    .padding(20)
}
```

Add the section:

```swift
private var detectedAccountsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Text("Detected Accounts")
                .font(.headline)
            Spacer()
            Button {
                viewModel.refreshDetectedAccounts()
            } label: {
                Label("Detect", systemImage: "magnifyingglass")
            }
        }

        if viewModel.detectedAccounts.isEmpty {
            Text("No local GitHub account was detected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.detectedAccounts) { account in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.username ?? account.gitUserName ?? "GitHub Account")
                            .lineLimit(1)
                        Text(detectedAccountSubtitle(account))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(account.confidence.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        viewModel.importDetectedAccount(id: account.id)
                    } label: {
                        Label("Add", systemImage: "plus.circle")
                    }
                    .disabled(account.gitUserEmail == nil)
                    .help(account.gitUserEmail == nil ? "Add an email before importing this account" : "Add detected account")
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private func detectedAccountSubtitle(_ account: DetectedGitAccount) -> String {
    if let email = account.gitUserEmail {
        return email
    }
    if account.warnings.isEmpty {
        return "Local GitHub configuration found"
    }
    return account.warnings[0]
}
```

- [ ] **Step 3: Add manual folder scan button flow**

Add a button beside `Detect` if the app target can import `AppKit` picker cleanly in this task:

```swift
Button {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
        viewModel.scanSelectedFolderForGitHubAccounts(url)
    }
} label: {
    Label("Scan Folder", systemImage: "folder.badge.gearshape")
}
```

If adding `NSOpenPanel` requires an import, add at the top:

```swift
import AppKit
```

- [ ] **Step 4: Build to verify UI compiles**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 5: Run core tests**

Run:

```bash
swift run GitAccountSwitcherCoreTestRunner
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/GitAccountSwitcherApp/SettingsView.swift
git commit -m "feat: show detected github accounts in settings"
```

---

### Task 9: Documentation And Release Notes

**Files:**
- Modify: `README.md`
- Modify: `docs/release-notes/v0.1.0.md`

- [ ] **Step 1: Update README**

Add a short section near the feature list:

```markdown
### Local GitHub Discovery

Git Account Switcher can suggest a GitHub account from local-only signals such as GitHub CLI configuration, global Git identity, SSH configuration, and GitHub remotes in a folder selected by the user.

Discovery does not call the GitHub API, does not log in to GitHub, does not read token values into app data, and does not scan the home directory automatically. A detected account is only a suggestion until the user imports it as a profile.
```

- [ ] **Step 2: Update release notes**

Add this bullet to `docs/release-notes/v0.1.0.md`:

```markdown
- Added local-only GitHub account discovery suggestions from Git, SSH, GitHub CLI config, and user-approved folder scans.
```

- [ ] **Step 3: Run build and tests**

Run:

```bash
swift build
swift run GitAccountSwitcherCoreTestRunner
```

Expected: both commands PASS.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/release-notes/v0.1.0.md
git commit -m "docs: document local github discovery"
```

---

### Task 10: Final Verification

**Files:**
- Inspect: all changed files

- [ ] **Step 1: Run final checks**

Run:

```bash
swift build
swift run GitAccountSwitcherCoreTestRunner
git status --short
```

Expected:

```text
swift build: succeeds
GitAccountSwitcherCoreTestRunner: reports all tests passed
git status --short: empty output
```

- [ ] **Step 2: Verify privacy constraints manually**

Inspect `GitHubLocalDiscoveryService` and confirm:

```text
Allowed commands only:
- git config --global --get user.name
- git config --global --get user.email
- git config --global --get credential.https://github.com.username
- git config --global --get credential.github.com.username
- gh --version
- ssh -G github.com

Forbidden commands absent:
- gh auth status
- gh api
- git ls-remote
- ssh -T
- curl
```

- [ ] **Step 3: Confirm no secret persistence**

Run:

```bash
rg -n "oauth_token|super-secret-token|httpsCredentialRef" Sources docs README.md
```

Expected:

```text
oauth_token appears only in parser tests or documentation examples.
super-secret-token appears only in parser tests.
httpsCredentialRef is set to nil during detected account import.
```

- [ ] **Step 4: Prepare handoff summary**

Write a short summary with:

```text
- Files changed
- Tests run
- Privacy constraints verified
- Any residual limitations, especially that remote owner is not treated as a certain username
```
