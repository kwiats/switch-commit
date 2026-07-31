import Foundation
import SwitchCommitAppLogic
import SwitchCommitCore

enum TestFailure: Error, CustomStringConvertible {
    case expectationFailed(String)

    var description: String {
        switch self {
        case .expectationFailed(let message):
            return message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure.expectationFailed(message)
    }
}

func expectRange(of needle: String, in haystack: String) throws -> Range<String.Index> {
    guard let range = haystack.range(of: needle) else {
        throw TestFailure.expectationFailed("expected to find \(needle)")
    }
    return range
}

func expectValue<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw TestFailure.expectationFailed(message)
    }
    return value
}

func expectThrows<T: Error & Equatable>(
    _ expectedError: T,
    _ operation: () throws -> Void,
    _ message: String
) throws {
    do {
        try operation()
    } catch let error as T {
        try expect(error == expectedError, "\(message): expected \(expectedError), got \(error)")
        return
    } catch {
        throw TestFailure.expectationFailed("\(message): unexpected error \(error)")
    }
    throw TestFailure.expectationFailed("\(message): expected error \(expectedError)")
}

func expectThrowsAny(_ operation: () throws -> Void, _ message: String) throws {
    do {
        try operation()
    } catch {
        return
    }
    throw TestFailure.expectationFailed("\(message): expected an error")
}

func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
}

extension DetectedGitAccount {
    var displaySummary: String {
        username ?? gitUserName ?? gitUserEmail ?? "GitHub Account"
    }
}

enum FakeLaunchAtLoginError: Error {
    case denied
}

final class FakeLaunchAtLoginManager: LaunchAtLoginManaging, @unchecked Sendable {
    var status: LaunchAtLoginStatus
    var enableCallCount = 0
    var disableCallCount = 0
    var errorToThrow: Error?

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func enable() throws {
        enableCallCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
        status = .enabled
    }

    func disable() throws {
        disableCallCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
        status = .disabled
    }
}

let tests: [(String, () throws -> Void)] = [
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
    }),
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
        try expect(signals[0].accessMethods == [.ssh], "gh ssh protocol should suggest ssh access")
        try expect(!String(describing: signals).contains("super-secret-token"), "token should never appear in parsed output")
    }),
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
    }),
    ("github cli hosts parser ignores non-exact protocol casing", {
        let yaml = """
        github.com:
            oauth_token: super-secret-token
            user: pawelkwiatkowski
            git_protocol: SSH
        """

        let signals = GitHubCLIHostsParser().signals(from: yaml)

        try expect(signals.count == 1, "parser should emit one signal")
        try expect(signals[0].accessMethods == [], "non-exact gh protocol casing should not suggest an access method")
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
    }),
    ("git remote parser recognizes github ssh https and ssh url remotes", {
        let parser = GitRemoteParser()

        let scp = parser.githubRemote(from: "git@github.com:pawelkwiatkowski/project.git")
        let https = parser.githubRemote(from: "https://github.com/pawelkwiatkowski/project.git")
        let sshURL = parser.githubRemote(from: "ssh://git@github.com/pawelkwiatkowski/project.git")
        let nonGitHub = parser.githubRemote(from: "git@gitlab.com:pawelkwiatkowski/project.git")
        let emptyPathComponent = parser.githubRemote(from: "git@github.com:pawelkwiatkowski//project.git")
        let extendedPath = parser.githubRemote(from: "https://github.com/pawelkwiatkowski/project/issues")
        let query = parser.githubRemote(from: "https://github.com/pawelkwiatkowski/project.git?token=x")

        try expect(scp == GitHubRemoteAccount(owner: "pawelkwiatkowski", repository: "project"), "scp-like ssh remote should parse")
        try expect(https == GitHubRemoteAccount(owner: "pawelkwiatkowski", repository: "project"), "https remote should parse")
        try expect(sshURL == GitHubRemoteAccount(owner: "pawelkwiatkowski", repository: "project"), "ssh url remote should parse")
        try expect(nonGitHub == nil, "non-github remote should not parse")
        try expect(emptyPathComponent == nil, "empty path component should not parse")
        try expect(extendedPath == nil, "extended repository path should not parse")
        try expect(query == nil, "repository query should not parse")
    }),
    ("git remote parser emits a privacy-safe signal", {
        let parser = GitRemoteParser()
        let signal = parser.signal(from: "https://github.com/pawelkwiatkowski/project.git")
        let sshSignal = parser.signal(from: "git@github.com:pawelkwiatkowski/project.git")
        let httpsSignal = parser.signal(from: "https://github.com/pawelkwiatkowski/project.git")

        try expect(signal?.confidence == .medium, "remote signal should have medium confidence")
        try expect(signal?.source == .repositoryRemote, "remote signal should identify repository remote source")
        try expect(signal?.hosts == ["github.com"], "remote signal should identify github.com")
        try expect(signal?.username == nil, "remote owner should not become a username")
        try expect(signal?.warnings == ["Remote owner 'pawelkwiatkowski' may be a user or an organization."], "remote signal should warn about owner ambiguity")
        try expect(sshSignal?.accessMethods == [.ssh], "ssh remote should suggest ssh access")
        try expect(httpsSignal?.accessMethods == [.https], "https remote should suggest https access")
    }),
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
    ("detected account merger combines access methods and warns on conflict", {
        let signals = [
            DetectionSignal(provider: .github, username: "pawel", accessMethods: [.ssh], confidence: .high, source: .githubCliHostsFile),
            DetectionSignal(provider: .github, username: "pawel", accessMethods: [.https], confidence: .medium, source: .repositoryRemote)
        ]

        let account = DetectedAccountMerger().merge(signals: signals, existingProfiles: []).first

        try expect(account?.accessMethods == [.ssh, .https], "merged account should preserve stable access method order")
        try expect(account?.warnings.contains("Local data points to both SSH and HTTPS access. Choose the method before import.") == true, "conflicting access methods should warn")
    }),
    ("detected account merger falls back to email id for unsafe username", {
        let signals = [
            DetectionSignal(
                provider: .github,
                username: "bad/name",
                gitUserEmail: "pawel@example.com",
                confidence: .high,
                source: .githubCliHostsFile
            )
        ]

        let account = DetectedAccountMerger().merge(signals: signals, existingProfiles: []).first

        try expect(account?.id == "github-pawel-example.com", "unsafe username should fall back to email-derived id")
    }),
    ("detected account merger separates conflicting github usernames", {
        let signals = [
            DetectionSignal(provider: .github, username: "alice", confidence: .high, source: .githubCliHostsFile),
            DetectionSignal(provider: .github, username: "bob", confidence: .medium, source: .gitCredentialUsername),
            DetectionSignal(provider: .github, gitUserName: "Global User", gitUserEmail: "global@example.com", confidence: .low, source: .globalGitConfig),
            DetectionSignal(provider: .github, sshKeyPath: "~/.ssh/id_ed25519", confidence: .medium, source: .sshResolvedConfig)
        ]

        let accounts = DetectedAccountMerger().merge(signals: signals, existingProfiles: [])

        try expect(accounts.map(\.username) == ["alice", "bob"], "conflicting usernames should produce separate candidates")
        try expect(accounts.allSatisfy { $0.gitUserEmail == nil }, "conflicting username candidates should not inherit global git email")
        try expect(accounts.allSatisfy { $0.sshKeyPath == nil }, "conflicting username candidates should not inherit ambiguous ssh key")
        try expect(accounts.allSatisfy { $0.warnings.contains("Conflicting local GitHub identities were detected. Complete this account before import.") }, "conflicting candidates should warn")
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
    }),
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
        let sshConfig = temporaryDirectory.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: ghConfig, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sshConfig, withIntermediateDirectories: true)
        try """
        github.com:
            oauth_token: secret-token
            user: pawelkwiatkowski
        """.write(to: ghConfig.appendingPathComponent("hosts.yml"), atomically: true, encoding: .utf8)
        try """
        Host github.com
            IdentityFile ~/.ssh/id_ed25519
        """.write(to: sshConfig.appendingPathComponent("config"), atomically: true, encoding: .utf8)

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
        let allowlistedCommands: Set<[String]> = [
            ["git", "config", "--global", "--get", "user.name"],
            ["git", "config", "--global", "--get", "user.email"],
            ["git", "config", "--global", "--get", "credential.https://github.com.username"],
            ["git", "config", "--global", "--get", "credential.github.com.username"],
            ["gh", "--version"],
            ["ssh", "-G", "github.com"]
        ]
        try expect(runner.commands.allSatisfy { allowlistedCommands.contains($0) }, "service must use only approved local commands")
    }),
    ("github local discovery ignores default ssh identity without explicit github ssh config", {
        final class FakeSSHRunner: CommandRunning {
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

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = GitHubLocalDiscoveryService(
            homeDirectory: temporaryDirectory,
            commandRunner: FakeSSHRunner()
        )

        let accounts = service.detect(existingProfiles: [])

        try expect(accounts.isEmpty, "default ssh identity should not create a github candidate without explicit github ssh config")
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
    }),
    ("github local discovery manual scan rejects symlinked git config outside selected folder", {
        let selectedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoGit = selectedRoot.appendingPathComponent("project/.git", isDirectory: true)
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outsideConfig = outsideRoot.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: repoGit, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try """
        [remote "origin"]
            url = git@github.com:outside-owner/private.git
        """.write(to: outsideConfig, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: repoGit.appendingPathComponent("config"),
            withDestinationURL: outsideConfig
        )

        let service = GitHubLocalDiscoveryService(
            homeDirectory: selectedRoot,
            commandRunner: ProcessCommandRunner()
        )

        let signals = service.repositoryRemoteSignals(in: selectedRoot)

        try expect(signals.isEmpty, "manual scan must not read git config symlinked outside selected folder")
    }),
    ("profile rejects empty commit identity", {
        try expectThrows(SwitchCommitError.emptyGitUserName, {
            _ = try GitProfile(
                id: "personal",
                displayName: "Personal",
                gitUserName: "",
                gitUserEmail: "me@example.com",
                sshKeyPath: "/Users/me/.ssh/id_ed25519",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
        }, "empty git user name should be rejected")
    }),
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
        try expectThrows(SwitchCommitError.emptySSHKeyPath, {
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
    }),
    ("profile rejects config injection characters", {
        try expectThrows(SwitchCommitError.unsafeConfigValue, {
            _ = try GitProfile(
                id: "personal",
                displayName: "Personal",
                gitUserName: "Personal User\n[alias]\n    leak = !cat ~/.ssh/id_ed25519",
                gitUserEmail: "me@example.com",
                sshKeyPath: "/Users/me/.ssh/id_ed25519",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
        }, "newlines in git user name should be rejected")

        try expectThrows(SwitchCommitError.unsafeConfigValue, {
            _ = try GitProfile(
                id: "personal",
                displayName: "Personal",
                gitUserName: "Personal User",
                gitUserEmail: "me@example.com",
                sshKeyPath: "/Users/me/.ssh/id_ed25519",
                hosts: ["github.com\n    ProxyCommand sh -c env"],
                httpsCredentialRef: nil,
                isDefault: true
            )
        }, "newlines in ssh hosts should be rejected")
    }),
    ("profile rejects identifiers that can escape managed filenames", {
        try expectThrows(SwitchCommitError.unsafeIdentifier, {
            _ = try GitProfile(
                id: "../work",
                displayName: "Work",
                gitUserName: "Work User",
                gitUserEmail: "work@example.com",
                sshKeyPath: "/Users/me/.ssh/id_work",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: false
            )
        }, "profile ids should be safe path components")
    }),
    ("switch commit paths default profiles url lives under managed config dir", {
        let url = SwitchCommitPaths.defaultProfilesURL(homeDirectory: URL(fileURLWithPath: "/Users/demo"))
        try expect(
            url.path == "/Users/demo/.config/git-account-switcher/profiles.json",
            "default profiles path should match managed config layout"
        )
    }),
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
        // Use "WORK" so id exact-match fails and display-name path is exercised
        let resolved = try ProfileReferenceResolver.resolve("WORK", in: profiles)
        try expect(resolved.displayName == "Work", "name lookup should be case-insensitive")
    }),
    ("profile reference resolver errors on unknown and ambiguous names", {
        let profiles = [
            try GitProfile(id: "a", displayName: "Work", gitUserName: "A", gitUserEmail: "a@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: true),
            try GitProfile(id: "b", displayName: "work", gitUserName: "B", gitUserEmail: "b@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: false)
        ]
        try expectThrows(ProfileReferenceError.notFound("missing"), { _ = try ProfileReferenceResolver.resolve("missing", in: profiles) }, "unknown should throw notFound")
        try expectThrows(ProfileReferenceError.ambiguous("work", candidates: ["a", "b"]), { _ = try ProfileReferenceResolver.resolve("work", in: profiles) }, "ambiguous display names should throw")
    }),
    ("profile reference resolver trims whitespace", {
        let profiles = [
            try GitProfile(id: "work", displayName: "Work", gitUserName: "W", gitUserEmail: "w@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: true)
        ]
        let resolved = try ProfileReferenceResolver.resolve("  work  ", in: profiles)
        try expect(resolved.id == "work", "whitespace should be trimmed before lookup")
    }),
    ("profile reference resolver prefers id over display name", {
        let profiles = [
            try GitProfile(id: "work", displayName: "Other", gitUserName: "W", gitUserEmail: "w@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: true),
            try GitProfile(id: "other", displayName: "work", gitUserName: "O", gitUserEmail: "o@example.com", accessMethod: .https, sshKeyPath: "", hosts: ["github.com"], httpsCredentialRef: nil, isDefault: false)
        ]
        let resolved = try ProfileReferenceResolver.resolve("work", in: profiles)
        try expect(resolved.id == "work", "id lookup should win over display name")
    }),
    ("profile store round trips metadata without secret payloads", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        let store = ProfileStore(fileURL: storeURL)
        let profile = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            sshKeyPath: "/Users/me/.ssh/id_work",
            hosts: ["github.com"],
            httpsCredentialRef: "git-account-switcher.work.https",
            isDefault: false
        )
        let rule = try FolderRule(
            id: "work-folder",
            path: "/Users/me/Work",
            profileId: "work",
            matchMode: .folderTree,
            enabled: true
        )

        try store.save(ProfileStoreData(profiles: [profile], rules: [rule]))

        let raw = try String(contentsOf: storeURL, encoding: .utf8)
        try expect(raw.contains("git-account-switcher.work.https"), "credential reference should be stored")
        try expect(!raw.contains("super-secret-token"), "secret payload should not be stored")

        let loaded = try store.load()
        try expect(loaded.profiles == [profile], "profiles should round trip")
        try expect(loaded.rules == [rule], "rules should round trip")
    }),
    ("profile store round trips persisted connection states", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        let store = ProfileStore(fileURL: storeURL)
        let profile = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            sshKeyPath: "/Users/me/.ssh/id_work",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let state = PersistedProfileConnectionState(
            profileId: "work",
            testedAt: "2026-07-30T12:00:00Z",
            results: [
                PersistedHostConnectionTestResult(
                    host: "github.com",
                    status: .connected,
                    message: "successfully authenticated"
                )
            ]
        )

        try store.save(ProfileStoreData(
            profiles: [profile],
            rules: [],
            profileConnectionStates: ["work": state]
        ))

        let raw = try String(contentsOf: storeURL, encoding: .utf8)
        try expect(raw.contains("profileConnectionStates"), "connection states should be persisted")
        try expect(!raw.contains("PRIVATE KEY"), "connection state should not contain secret payloads")

        let loaded = try store.load()
        try expect(loaded.profileConnectionStates["work"] == state, "connection state should round trip")
    }),
    ("profile store decodes legacy json without connection states", {
        let json = """
        {
          "profiles": [],
          "rules": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ProfileStoreData.self, from: json)

        try expect(decoded.profileConnectionStates.isEmpty, "legacy store should default connection states to empty")
    }),
    ("folder rule rejects unsafe config paths and identifiers", {
        try expectThrows(SwitchCommitError.unsafeConfigValue, {
            _ = try FolderRule(
                id: "work-folder",
                path: "/Users/me/Work\n[alias]\n    leak = !env",
                profileId: "work",
                matchMode: .folderTree,
                enabled: true
            )
        }, "folder paths should not allow newline injection")

        try expectThrows(SwitchCommitError.unsafeIdentifier, {
            _ = try FolderRule(
                id: "work-folder",
                path: "/Users/me/Work",
                profileId: "../work",
                matchMode: .folderTree,
                enabled: true
            )
        }, "folder rule profile ids should be safe path components")
    }),
    ("git config generator emits profile and ordered includes", {
        let profile = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            sshKeyPath: "~/.ssh/id_work",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: false
        )
        let generator = GitConfigGenerator()
        let profileConfig = generator.profileConfig(for: profile)
        let expectedProfileConfig = """
        [user]
            name = Work User
            email = work@example.com
        [core]
            sshCommand = ssh -i '~/.ssh/id_work' -F ~/.ssh/config

        """
        try expect(profileConfig == expectedProfileConfig, "ssh profile config should remain byte stable")
        try expect(profileConfig.contains("[user]"), "profile config should contain user section")
        try expect(profileConfig.contains("name = Work User"), "profile config should contain name")
        try expect(profileConfig.contains("email = work@example.com"), "profile config should contain email")
        try expect(profileConfig.contains("sshCommand = ssh -i '~/.ssh/id_work' -F ~/.ssh/config"), "profile config should contain ssh command")

        let includeConfig = generator.rootIncludeConfig(
            globalConfigPath: "~/.config/git-account-switcher/global.gitconfig",
            rulesConfigPath: "~/.config/git-account-switcher/rules.gitconfig"
        )
        let globalRange = try expectRange(of: "global.gitconfig", in: includeConfig)
        let rulesRange = try expectRange(of: "rules.gitconfig", in: includeConfig)
        try expect(globalRange.lowerBound < rulesRange.lowerBound, "global include should come before folder rules")

        let rule = try FolderRule(id: "work", path: "/Users/me/Work", profileId: "work", matchMode: .folderTree, enabled: true)
        let rulesConfig = generator.rulesConfig(rules: [rule], profilesDirectory: "~/.config/git-account-switcher/profiles")
        try expect(rulesConfig.contains("[includeIf \"gitdir:/Users/me/Work/**\"]"), "folder tree rule should match children")
        try expect(rulesConfig.contains("path = ~/.config/git-account-switcher/profiles/work.gitconfig"), "rule should include profile config")
    }),
    ("git config generator shell quotes ssh identity path", {
        let profile = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            sshKeyPath: "/Users/me/My Keys/id_work'; env",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: false
        )
        let config = GitConfigGenerator().profileConfig(for: profile)
        try expect(config.contains("sshCommand = ssh -i '/Users/me/My Keys/id_work'\\''; env' -F ~/.ssh/config"), "ssh key path should be shell quoted")
    }),
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
    }),
    ("ssh config generator emits managed identity blocks", {
        let profile = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            sshKeyPath: "~/.ssh/id_work",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: false
        )
        let config = SSHConfigGenerator().managedConfig(for: [profile])
        try expect(config.contains("# Profile: Work"), "config should name owning profile")
        try expect(config.contains("Host github.com"), "config should contain host")
        try expect(config.contains("IdentityFile ~/.ssh/id_work"), "config should contain identity file")
        try expect(config.contains("IdentitiesOnly yes"), "config should force selected identity")
    }),
    ("ssh config generator skips https profiles", {
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

        let config = SSHConfigGenerator().managedConfig(for: [profile])

        try expect(config.isEmpty, "https profiles should not emit managed ssh config blocks")
    }),
    ("safe file writer constrains writes and creates backups", {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let writer = SafeFileWriter(allowedRoots: [managed], backupDirectory: backups)
        let target = managed.appendingPathComponent("global.gitconfig")

        try writer.write("first", to: target)
        let firstContent = try String(contentsOf: target, encoding: .utf8)
        try expect(firstContent == "first", "writer should write managed file")

        try writer.write("second", to: target)
        let secondContent = try String(contentsOf: target, encoding: .utf8)
        try expect(secondContent == "second", "writer should replace managed file")
        let backupFiles = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        try expect(backupFiles.contains { $0.contains("global.gitconfig") }, "writer should backup previous file")

        let outside = root.appendingPathComponent("outside.gitconfig")
        try expectThrows(SwitchCommitError.writeOutsideManagedRoots, {
            try writer.write("bad", to: outside)
        }, "outside writes should be rejected")
    }),
    ("safe file writer rejects writes through symlinked directories", {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let linked = managed.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)

        let writer = SafeFileWriter(allowedRoots: [managed], backupDirectory: backups)
        let target = linked.appendingPathComponent("escaped.gitconfig")
        try expectThrows(SwitchCommitError.writeOutsideManagedRoots, {
            try writer.write("bad", to: target)
        }, "symlinked parent directories should not escape managed roots")
        try expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("escaped.gitconfig").path), "outside file should not be written")
    }),
    ("diagnostics run local git config commands and report warnings", {
        final class FakeRunner: CommandRunning {
            var commands: [[String]] = []

            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                commands.append([command] + arguments)
                if arguments.contains("core.sshCommand") {
                    return CommandResult(exitCode: 1, standardOutput: "", standardError: "missing")
                }
                return CommandResult(exitCode: 0, standardOutput: "file\tvalue", standardError: "")
            }
        }

        let runner = FakeRunner()
        let service = DiagnosticsService(commandRunner: runner)
        let report = service.inspectGitIdentity(at: URL(fileURLWithPath: "/tmp/repo"))
        try expect(runner.commands.count == 3, "diagnostics should run three local git config commands")
        try expect(runner.commands.allSatisfy { $0.first == "git" }, "diagnostics should only call git")
        try expect(runner.commands.allSatisfy { $0.contains("--includes") }, "diagnostics should resolve managed includes")
        try expect(runner.commands.allSatisfy { $0.contains("--show-origin") }, "diagnostics should show origin")
        try expect(report.warnings.contains { $0.contains("core.sshCommand") }, "failed command should become warning")
    }),
    ("diagnostics builds ssh connection test commands for git hosts", {
        let service = DiagnosticsService()

        let githubCommand = service.sshConnectionTestCommand(host: "github.com")
        let gitlabCommand = service.sshConnectionTestCommand(host: "gitlab.com")

        try expect(githubCommand.command == "ssh", "github command should use ssh")
        try expect(githubCommand.arguments == ["-o", "BatchMode=yes", "-T", "git@github.com"], "github command should use git user")
        try expect(gitlabCommand.command == "ssh", "generic host command should use ssh")
        try expect(gitlabCommand.arguments == ["-o", "BatchMode=yes", "-T", "git@gitlab.com"], "generic host command should use git user")
    }),
    ("diagnostics interprets manual ssh connection results", {
        final class FakeConnectionRunner: CommandRunning {
            var result: CommandResult

            init(result: CommandResult) {
                self.result = result
            }

            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                result
            }
        }

        let githubRunner = FakeConnectionRunner(result: CommandResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "Hi pawelkwiatkowski! You've successfully authenticated, but GitHub does not provide shell access."
        ))
        let githubResult = DiagnosticsService(commandRunner: githubRunner).testSSHConnection(host: "github.com")

        let failedRunner = FakeConnectionRunner(result: CommandResult(
            exitCode: 255,
            standardOutput: "",
            standardError: "Permission denied (publickey)."
        ))
        let failedResult = DiagnosticsService(commandRunner: failedRunner).testSSHConnection(host: "gitlab.com")

        try expect(githubResult.status == .connected, "github success text should count as connected")
        try expect(githubResult.message.contains("successfully authenticated"), "github success message should be preserved")
        try expect(failedResult.status == .failed, "non-success result should fail")
        try expect(failedResult.message.contains("Permission denied"), "failure message should be preserved")
    }),
    ("keychain identifiers are app and profile scoped", {
        let identifier = KeychainCredentialIdentifier(profileId: "work", purpose: "https")
        try expect(identifier.rawValue == "git-account-switcher.work.https", "identifier should be namespaced")

        let store = InMemoryKeychainStore()
        try store.save("token-value", for: identifier)
        let savedValue = try store.read(identifier)
        try expect(savedValue == "token-value", "fake keychain should read saved value")
        try store.delete(identifier)
        let deletedValue = try store.read(identifier)
        try expect(deletedValue == nil, "delete should use the same identifier")
    }),
    ("profile settings manager adds a valid profile and selects it", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: []
        )

        try manager.addProfile()

        try expect(manager.profiles.count == 1, "add should create one profile")
        try expect(manager.activeProfileId == manager.profiles[0].id, "added profile should become active")
        try expect(manager.selectedProfileId == manager.profiles[0].id, "added profile should become selected")
        let loaded = try ProfileStore(fileURL: storeURL).load()
        try expect(loaded.profiles == manager.profiles, "added profile should persist")
    }),
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
        let profile = manager.profiles[0]
        try expect(profile.id == "github-pawelkwiatkowski", "profile id should use detected id")
        try expect(profile.displayName == "pawelkwiatkowski", "display name should prefer username")
        try expect(profile.gitUserName == "Pawel Kwiatkowski", "import should map git user name")
        try expect(profile.gitUserEmail == "pawel@example.com", "import should map git user email")
        try expect(profile.sshKeyPath == "~/.ssh/id_ed25519", "import should map ssh key path")
        try expect(profile.hosts == ["github.com"], "import should map hosts")
        try expect(profile.httpsCredentialRef == nil, "import must not store credential refs")
        try expect(profile.isDefault, "first imported profile should be default")
        try expect(manager.activeProfileId == "github-pawelkwiatkowski", "first imported profile should become active")
        try expect(manager.selectedProfileId == "github-pawelkwiatkowski", "imported profile should become selected")
        try expect(
            manager.statusMessage == "Added detected GitHub account pawelkwiatkowski.",
            "import should report the added account"
        )
        let loaded = try ProfileStore(fileURL: storeURL).load()
        try expect(loaded.profiles == [profile], "imported profile should persist all mapped values")
        try expect(loaded.profiles[0].gitUserName == "Pawel Kwiatkowski", "persisted profile should retain git user name")
        try expect(loaded.profiles[0].gitUserEmail == "pawel@example.com", "persisted profile should retain git user email")
        try expect(loaded.profiles[0].sshKeyPath == "~/.ssh/id_ed25519", "persisted profile should retain ssh key path")
        try expect(loaded.profiles[0].hosts == ["github.com"], "persisted profile should retain hosts")
        try expect(loaded.profiles[0].isDefault, "persisted imported profile should be default")
    }),
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
            accessMethods: [.https],
            hosts: ["github.com"],
            confidence: .high,
            sources: [.githubCliHostsFile],
            warnings: []
        )

        try manager.importDetectedAccount(account)

        try expect(manager.profiles[0].accessMethod == .https, "imported profile should use https")
        try expect(manager.profiles[0].sshKeyPath == "", "https import should not synthesize ssh key")
    }),
    ("profile settings import keeps pure ssh access with default ssh key", {
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
            accessMethods: [.ssh],
            hosts: ["github.com"],
            confidence: .high,
            sources: [.githubCliHostsFile],
            warnings: []
        )

        try manager.importDetectedAccount(account)

        try expect(manager.profiles[0].accessMethod == .ssh, "pure ssh import should use ssh")
        try expect(manager.profiles[0].sshKeyPath == "~/.ssh/id_ed25519", "pure ssh import without a key should use default ssh key")
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

        try expectThrows(SwitchCommitError.emptyGitUserEmail, {
            try manager.importDetectedAccount(account)
        }, "incomplete detected account should not be saved as profile")
        try expect(manager.profiles.isEmpty, "incomplete detected account should not mutate profiles")
        let loaded = try ProfileStore(fileURL: storeURL).load()
        try expect(loaded.profiles.isEmpty, "incomplete detected account should not persist a profile")
    }),
    ("profile settings manager preserves state when detected account persistence fails", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let storageURL = temporaryDirectory.appendingPathComponent("storage", isDirectory: true)
        let storeURL = storageURL.appendingPathComponent("profiles.json")
        let existingProfile = try GitProfile(
            id: "existing",
            displayName: "Existing",
            gitUserName: "Existing User",
            gitUserEmail: "existing@example.com",
            sshKeyPath: "~/.ssh/id_existing",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [existingProfile]
        )
        try FileManager.default.removeItem(at: storageURL)
        try Data("not a directory".utf8).write(to: storageURL)
        let account = DetectedGitAccount(
            id: "github-failing-import",
            provider: .github,
            username: "failing-import",
            gitUserName: "Failing Import",
            gitUserEmail: "failing@example.com",
            sshKeyPath: "~/.ssh/id_failing",
            hosts: ["github.com"],
            confidence: .high,
            sources: [.githubCliHostsFile],
            warnings: []
        )
        let originalProfiles = manager.profiles
        let originalSelectedProfileId = manager.selectedProfileId
        let originalActiveProfileId = manager.activeProfileId
        let originalStatusMessage = manager.statusMessage

        try expectThrowsAny({
            try manager.importDetectedAccount(account)
        }, "persistence failure should be reported")
        try expect(manager.profiles == originalProfiles, "failed import should not mutate profiles")
        try expect(manager.selectedProfileId == originalSelectedProfileId, "failed import should preserve selection")
        try expect(manager.activeProfileId == originalActiveProfileId, "failed import should preserve active profile")
        try expect(manager.statusMessage == originalStatusMessage, "failed import should preserve status")
    }),
    ("profile settings manager updates active display name", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        let profile = try GitProfile(
            id: "personal",
            displayName: "Personal",
            gitUserName: "Personal User",
            gitUserEmail: "me@example.com",
            sshKeyPath: "~/.ssh/id_ed25519",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [profile]
        )

        try manager.updateSelectedProfileDisplayName("Top Name")

        try expect(manager.activeProfile?.displayName == "Top Name", "active profile display name should update")
    }),
    ("profile settings manager preserves access method state when apply fails", {
        struct FailingInstaller: GitConfigInstalling {
            func apply(profiles: [GitProfile], rules: [FolderRule], activeProfile: GitProfile?) throws {
                throw TestFailure.expectationFailed("apply failed")
            }
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        let profile = try GitProfile(
            id: "personal",
            displayName: "Personal",
            gitUserName: "Personal User",
            gitUserEmail: "me@example.com",
            sshKeyPath: "~/.ssh/id_ed25519",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [profile],
            gitConfigInstaller: FailingInstaller()
        )
        let originalProfiles = manager.profiles
        let originalSelectedProfileId = manager.selectedProfileId
        let originalActiveProfileId = manager.activeProfileId

        try expectThrowsAny({
            try manager.updateSelectedProfileAccessMethod(.https)
        }, "apply failure should be reported")

        try expect(manager.profiles == originalProfiles, "failed access method update should preserve profiles")
        try expect(manager.selectedProfileId == originalSelectedProfileId, "failed access method update should preserve selection")
        try expect(manager.activeProfileId == originalActiveProfileId, "failed access method update should preserve active profile")
        let loaded = try ProfileStore(fileURL: storeURL).load()
        try expect(loaded.profiles == originalProfiles, "failed access method update should preserve persisted profiles")
    }),
    ("profile settings manager preserves access method state when save fails", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let storageURL = temporaryDirectory.appendingPathComponent("storage", isDirectory: true)
        let storeURL = storageURL.appendingPathComponent("profiles.json")
        let profile = try GitProfile(
            id: "personal",
            displayName: "Personal",
            gitUserName: "Personal User",
            gitUserEmail: "me@example.com",
            sshKeyPath: "~/.ssh/id_ed25519",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [profile],
            gitConfigInstaller: ManagedGitConfigInstaller(homeDirectory: temporaryDirectory)
        )
        try manager.switchGlobalProfile(to: profile)
        try FileManager.default.removeItem(at: storageURL)
        try Data("not a directory".utf8).write(to: storageURL)
        let originalProfiles = manager.profiles
        let originalSelectedProfileId = manager.selectedProfileId
        let originalActiveProfileId = manager.activeProfileId

        try expectThrowsAny({
            try manager.updateSelectedProfileAccessMethod(.https)
        }, "save failure should be reported")

        try expect(manager.profiles == originalProfiles, "failed access method save should preserve profiles")
        try expect(manager.selectedProfileId == originalSelectedProfileId, "failed access method save should preserve selection")
        try expect(manager.activeProfileId == originalActiveProfileId, "failed access method save should preserve active profile")
        let globalConfigURL = temporaryDirectory
            .appendingPathComponent(".config/git-account-switcher/global.gitconfig")
        let globalConfig = try String(contentsOf: globalConfigURL, encoding: .utf8)
        try expect(globalConfig.contains("sshCommand"), "failed access method save should keep generated config aligned with persisted ssh profile")
    }),
    ("profile settings manager applies switched global profile to managed git config", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        let personal = try GitProfile(
            id: "personal",
            displayName: "Personal",
            gitUserName: "Personal User",
            gitUserEmail: "me@example.com",
            sshKeyPath: "~/.ssh/id_ed25519",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let work = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            sshKeyPath: "~/.ssh/id_work",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: false
        )
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [personal, work],
            gitConfigInstaller: ManagedGitConfigInstaller(homeDirectory: temporaryDirectory)
        )

        try manager.switchGlobalProfile(to: work)

        let globalConfigURL = temporaryDirectory
            .appendingPathComponent(".config/git-account-switcher/global.gitconfig")
        let globalConfig = try String(contentsOf: globalConfigURL, encoding: .utf8)
        try expect(globalConfig.contains("name = Work User"), "global config should contain switched git user name")
        try expect(globalConfig.contains("email = work@example.com"), "global config should contain switched git user email")
        try expect(!globalConfig.contains("me@example.com"), "global config should not retain previous global email")

        let rootConfig = try String(
            contentsOf: temporaryDirectory.appendingPathComponent(".gitconfig"),
            encoding: .utf8
        )
        try expect(rootConfig.contains("path = ~/.config/git-account-switcher/global.gitconfig"), "root git config should include managed global config")
        try expect(rootConfig.contains("path = ~/.config/git-account-switcher/rules.gitconfig"), "root git config should include managed rules config")
    }),
    ("profile settings manager keeps selection valid when deleting profiles", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        let first = try GitProfile(
            id: "first",
            displayName: "First",
            gitUserName: "First User",
            gitUserEmail: "first@example.com",
            sshKeyPath: "~/.ssh/id_first",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let second = try GitProfile(
            id: "second",
            displayName: "Second",
            gitUserName: "Second User",
            gitUserEmail: "second@example.com",
            sshKeyPath: "~/.ssh/id_second",
            hosts: ["gitlab.com"],
            httpsCredentialRef: nil,
            isDefault: false
        )
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [first, second]
        )

        try manager.deleteSelectedProfile()
        try expect(manager.profiles.map(\.id) == ["second"], "delete should remove selected profile")
        try expect(manager.activeProfileId == "second", "remaining profile should become active")

        try manager.deleteSelectedProfile()
        try expect(manager.profiles.isEmpty, "second delete should remove last profile")
        try expect(manager.activeProfileId == nil, "active profile should clear after deleting last profile")
        try expect(manager.selectedProfileId == nil, "selected profile should clear after deleting last profile")
    }),
    ("profile settings manager resets https access", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        let identifier = KeychainCredentialIdentifier(profileId: "work", purpose: "https")
        let profile = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            sshKeyPath: "~/.ssh/id_work",
            hosts: ["github.com"],
            httpsCredentialRef: identifier.rawValue,
            isDefault: true
        )
        let keychain = InMemoryKeychainStore()
        try keychain.save("secret", for: identifier)
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: keychain,
            seedProfiles: [profile]
        )

        try manager.resetAccessForSelectedProfile()

        let resetValue = try keychain.read(identifier)
        try expect(resetValue == nil, "reset should delete keychain value")
        try expect(manager.profiles[0].httpsCredentialRef == nil, "reset should clear credential reference")
    }),
    ("app view model refreshes and imports detected github accounts", {
        try MainActor.assumeIsolated {
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
                        Thread.sleep(forTimeInterval: 0.2)
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
            try expect(
                viewModel.detectedAccounts.isEmpty,
                "refresh should defer local discovery work from the main actor"
            )
            try expect(
                waitUntil { viewModel.detectedAccounts.count == 1 },
                "view model should eventually expose detected account"
            )

            viewModel.importDetectedAccount(id: "github-pawelkwiatkowski")
            try expect(viewModel.profiles.count == 1, "import should create profile")
            try expect(viewModel.profiles[0].displayName == "pawelkwiatkowski", "profile should use detected username")
            try expect(
                waitUntil { viewModel.detectedAccounts.isEmpty },
                "import should refresh suggestions and remove duplicate"
            )

            viewModel.importDetectedAccount(id: "github-pawelkwiatkowski")
            try expect(
                viewModel.settingsMessage == "Detected account is no longer available.",
                "stale detected account imports should be reported"
            )
        }
    }),
    ("app view model filters stale detected accounts against current profiles", {
        try MainActor.assumeIsolated {
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let ghConfig = temporaryDirectory.appendingPathComponent(".config/gh", isDirectory: true)
            try FileManager.default.createDirectory(at: ghConfig, withIntermediateDirectories: true)
            try """
            github.com:
                user: pawelkwiatkowski
            """.write(to: ghConfig.appendingPathComponent("hosts.yml"), atomically: true, encoding: .utf8)

            final class SlowDiscoveryRunner: CommandRunning {
                func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                    if command == "git", arguments == ["config", "--global", "--get", "user.name"] {
                        Thread.sleep(forTimeInterval: 0.2)
                        return CommandResult(exitCode: 0, standardOutput: "Pawel Kwiatkowski\n", standardError: "")
                    }
                    if command == "git", arguments == ["config", "--global", "--get", "user.email"] {
                        return CommandResult(exitCode: 0, standardOutput: "pawel@example.com\n", standardError: "")
                    }
                    return CommandResult(exitCode: 1, standardOutput: "", standardError: "missing")
                }
            }

            let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
            let discovery = GitHubLocalDiscoveryService(
                homeDirectory: temporaryDirectory,
                commandRunner: SlowDiscoveryRunner()
            )
            let viewModel = AppViewModel(
                profiles: [],
                profileStore: ProfileStore(fileURL: storeURL),
                keychainStore: InMemoryKeychainStore(),
                githubDiscoveryService: discovery
            )

            viewModel.refreshDetectedAccounts()
            viewModel.addProfile()
            viewModel.updateSelectedProfileDisplayName("pawelkwiatkowski")
            viewModel.updateSelectedProfileGitUserEmail("pawel@example.com")

            try expect(
                waitUntil { viewModel.settingsMessage == "No local GitHub account was detected." },
                "stale detection results should be deduped against current profiles"
            )
            try expect(viewModel.detectedAccounts.isEmpty, "stale duplicate suggestion should not remain visible")
        }
    }),
    ("app view model creates editable profile for detected account without email", {
        try MainActor.assumeIsolated {
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let ghConfig = temporaryDirectory.appendingPathComponent(".config/gh", isDirectory: true)
            try FileManager.default.createDirectory(at: ghConfig, withIntermediateDirectories: true)
            try """
            github.com:
                user: pawelkwiatkowski
                git_protocol: https
            """.write(to: ghConfig.appendingPathComponent("hosts.yml"), atomically: true, encoding: .utf8)

            final class EmptyDiscoveryRunner: CommandRunning {
                func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                    CommandResult(exitCode: 1, standardOutput: "", standardError: "missing")
                }
            }

            let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
            let discovery = GitHubLocalDiscoveryService(
                homeDirectory: temporaryDirectory,
                commandRunner: EmptyDiscoveryRunner()
            )
            let viewModel = AppViewModel(
                profiles: [],
                profileStore: ProfileStore(fileURL: storeURL),
                keychainStore: InMemoryKeychainStore(),
                githubDiscoveryService: discovery
            )

            viewModel.refreshDetectedAccounts()
            try expect(
                waitUntil { !viewModel.detectedAccounts.isEmpty && viewModel.detectedAccounts.first?.gitUserEmail == nil },
                "email-less detected account should be exposed for completion"
            )
            let detectedId = try expectValue(viewModel.detectedAccounts.first?.id, "detected account should have an id")

            viewModel.completeDetectedAccount(id: detectedId)

            try expect(viewModel.profiles.count == 1, "completion should create an editable profile")
            try expect(viewModel.profiles[0].displayName == "pawelkwiatkowski", "completion should prefill display name")
            try expect(viewModel.profiles[0].gitUserName == "pawelkwiatkowski", "completion should prefill git user name")
            try expect(viewModel.profiles[0].gitUserEmail == "user1@example.com", "completion should keep the editable default email")
            try expect(viewModel.profiles[0].accessMethod == .https, "completion should preserve detected https access")
            try expect(viewModel.profiles[0].sshKeyPath == "", "completion should not synthesize an ssh key for detected https access")
            try expect(viewModel.detectedAccounts.isEmpty, "completed suggestion should be removed")
            try expect(viewModel.settingsMessage == "Complete the detected GitHub account before using it.", "completion should explain next step")
        }
    }),
    ("app view model exposes Switch Commit update presentation", {
        final class RecordingUpdateChecker: AppUpdateChecking {
            var canCheckForUpdates = true
            private(set) var checkCount = 0

            func checkForUpdates() {
                checkCount += 1
            }
        }

        let checker = RecordingUpdateChecker()
        let viewModel = AppViewModel(
            profiles: [],
            keychainStore: InMemoryKeychainStore(),
            updateChecker: checker,
            bundleInfo: AppBundleInfo(
                shortVersion: "1.2.3",
                buildVersion: "45"
            )
        )

        try expect(viewModel.updatePresentation.productName == "Switch Commit", "updates should use the customer-facing product name")
        try expect(viewModel.updatePresentation.installedVersion == "1.2.3 (45)", "updates should show semantic version and build")
        try expect(viewModel.updatePresentation.canCheckForUpdates, "manual update checks should be enabled when checker allows it")
        try expect(viewModel.updatePresentation.privacyNote == "Checks the public Switch Commit release channel only after you click.", "privacy note should explain manual network access")

        viewModel.checkForUpdates()

        try expect(checker.checkCount == 1, "manual update check should call the injected checker once")
        try expect(viewModel.settingsMessage == "Checking Switch Commit updates...", "manual check should show a user-initiated status message")
    }),
    ("app view model reports disabled update checker without network access", {
        final class DisabledRecordingUpdateChecker: AppUpdateChecking {
            var canCheckForUpdates = false
            private(set) var checkCount = 0

            func checkForUpdates() {
                checkCount += 1
            }
        }

        let checker = DisabledRecordingUpdateChecker()
        let viewModel = AppViewModel(
            profiles: [],
            keychainStore: InMemoryKeychainStore(),
            updateChecker: checker,
            bundleInfo: AppBundleInfo(
                shortVersion: nil,
                buildVersion: nil
            )
        )

        try expect(viewModel.updatePresentation.installedVersion == "Development Build", "missing bundle version should use a debug-friendly fallback")
        try expect(!viewModel.updatePresentation.canCheckForUpdates, "presentation should reflect disabled checker")

        viewModel.checkForUpdates()

        try expect(checker.checkCount == 0, "disabled checker must not be called")
        try expect(viewModel.settingsMessage == "Updates are not available in this build.", "disabled checker should explain why nothing happened")
    }),
    ("sparkle adapter does not start automatic update cycle at initialization", {
        let adapterURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SwitchCommitApp/SparkleAppUpdateChecker.swift")
        let source = try String(contentsOf: adapterURL, encoding: .utf8)

        try expect(source.contains("startingUpdater: false"), "sparkle adapter should not start updater during initialization")
        try expect(!source.contains("startingUpdater: true"), "sparkle adapter must not start Sparkle automatically")
        try expect(source.contains("hasReleaseChannelConfiguration"), "sparkle adapter should gate checks on release channel configuration")
        try expect(source.contains("SUFeedURL"), "sparkle adapter should require an appcast URL before enabling checks")
        try expect(source.contains("SUPublicEDKey"), "sparkle adapter should require a public EdDSA key before enabling checks")
        try expect(
            source.contains("hasReleaseChannelConfiguration && (!hasStartedUpdater || updaterController.updater.canCheckForUpdates)"),
            "sparkle adapter should only enable checks before updater startup when release channel config exists"
        )
        try expect(source.contains("automaticallyChecksForUpdates = false"), "sparkle adapter should keep automatic checks disabled")
        try expect(source.contains("automaticallyDownloadsUpdates = false"), "sparkle adapter should keep automatic downloads disabled")
        try expect(source.contains("updaterShouldPromptForPermissionToCheck"), "sparkle adapter should suppress permission prompts")
        try expect(source.contains("feedParameters"), "sparkle adapter should return no feed parameters")
        try expect(!source.contains("checkForUpdatesInBackground"), "sparkle adapter must not perform background update checks")
    }),
    ("release build script embeds Switch Commit Sparkle channel configuration", {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Scripts/build-release.sh")
        let source = try String(contentsOf: scriptURL, encoding: .utf8)

        try expect(
            source.contains("release_channel_base_url=\"https://kwiats.github.io/switch-commit-release-channel\"")
                && source.contains("sparkle_feed_url=\"${release_channel_base_url}/appcast.xml\""),
            "release script should embed the public Switch Commit appcast URL"
        )
        try expect(
            source.contains("x4XXCgBb5YuShR9DnY81L9bPJ+6vFaKeL46WK/fEte8="),
            "release script should embed the Sparkle public EdDSA key"
        )
        try expect(source.contains("<key>SUFeedURL</key>"), "release Info.plist should include SUFeedURL")
        try expect(source.contains("<key>SUPublicEDKey</key>"), "release Info.plist should include SUPublicEDKey")
        try expect(source.contains("<key>SUEnableAutomaticChecks</key>"), "release Info.plist should explicitly configure automatic checks")
        try expect(source.contains("<false/>"), "release Info.plist should keep automatic checks disabled")
        try expect(source.contains("Contents/Frameworks"), "release script should create a Frameworks directory in the app bundle")
        try expect(source.contains("Sparkle.framework"), "release script should copy Sparkle.framework into the app bundle")
        try expect(source.contains("@executable_path/../Frameworks"), "release script should add an app bundle Frameworks rpath")
        try expect(source.contains("sparkle_framework_destination"), "release script should sign bundled Sparkle.framework explicitly")
    }),
    ("release build script keeps appcast and artifact URLs on the public release channel", {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Scripts/build-release.sh")
        let source = try String(contentsOf: scriptURL, encoding: .utf8)

        try expect(
            source.contains("release_channel_base_url=\"https://kwiats.github.io/switch-commit-release-channel\""),
            "release script should keep the public channel base URL in one place"
        )
        try expect(
            source.contains("sparkle_feed_url=\"${release_channel_base_url}/appcast.xml\""),
            "release script should derive appcast URL from the public channel base URL"
        )
        try expect(source.contains("app_name=\"Switch Commit\""), "release script should ship Switch Commit.app")
        try expect(source.contains("binary_name=\"SwitchCommitApp\""), "release script should build SwitchCommitApp")
        try expect(
            source.contains("sparkle_artifact_url=\"https://github.com/kwiats/switch-commit-release-channel/releases/download/v${version}/SwitchCommit-v${version}-macOS.dmg\""),
            "release script should derive DMG artifact URL from GitHub Releases"
        )
        try expect(source.contains("hdiutil create"), "release script should create a DMG with hdiutil")
        try expect(source.contains("Applications"), "release script should include an Applications symlink in the DMG")
        try expect(!source.contains("macOS.zip"), "release script should not publish a ZIP artifact")
        try expect(
            source.contains("release-url.txt"),
            "release script should write the public artifact URL next to release artifacts"
        )
    }),
    ("release channel publisher signs appcast with Sparkle EdDSA key from standard input", {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Scripts/publish-release-channel.sh")
        let source = try String(contentsOf: scriptURL, encoding: .utf8)

        try expect(source.contains("SPARKLE_PRIVATE_ED_KEY"), "publisher should require the Sparkle private EdDSA key from the environment")
        try expect(source.contains("normalized_private_key"), "publisher should normalize the private key secret before signing")
        try expect(source.contains("tr -d '[:space:]'"), "publisher should tolerate accidental whitespace in the private key secret")
        try expect(source.contains("base64 --decode"), "publisher should validate the private key secret before invoking Sparkle")
        try expect(source.contains("must be the base64 contents exported by Sparkle generate_keys -x"), "publisher should explain the expected secret format")
        try expect(source.contains("generate_appcast"), "publisher should invoke Sparkle generate_appcast")
        try expect(source.contains("--ed-key-file -"), "publisher should pass the EdDSA key via standard input")
        try expect(source.contains("gh release"), "publisher should publish artifacts through GitHub Releases")
        try expect(source.contains("kwiats/switch-commit-release-channel"), "publisher should target the public channel repository for Releases")
        try expect(source.contains("SwitchCommit-v${version}-macOS.dmg"), "publisher should upload the release DMG")
        try expect(!source.contains("macOS.zip"), "publisher should not publish a ZIP artifact")
        try expect(source.contains("checksum_name=\"${artifact_name}.sha256\""), "publisher should upload the checksum")
        try expect(source.contains("docs/release-notes/v${version}.md"), "publisher should attach matching release notes when present")
        try expect(
            source.contains("--download-url-prefix \"${github_download_prefix}/\""),
            "publisher should put GitHub Releases download URLs inside appcast enclosures"
        )
        try expect(source.contains("version.txt"), "publisher should write the latest version marker for Pages")
        try expect(source.contains("docs/release-channel/index.html"), "publisher should render the landing page from the source template")
        try expect(source.contains("rm -rf"), "publisher should remove obsolete Pages artifact folders")
        try expect(!source.contains("release_channel_assets_dir=\"${release_channel_dir}/release\""), "publisher should not copy artifacts into a Pages release folder")
        try expect(source.contains("-o \"${release_channel_dir}/appcast.xml\""), "publisher should keep appcast.xml at the release channel root")
    }),
    ("tag release workflow publishes public GitHub Pages appcast channel", {
        let workflowURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".github/workflows/release.yml")
        let source = try String(contentsOf: workflowURL, encoding: .utf8)

        try expect(source.contains("tags:"), "release workflow should run for tags")
        try expect(source.contains("'v*'"), "release workflow should limit publishing to v-prefixed tags")
        try expect(source.contains("Scripts/pr-checks.sh"), "release workflow should run local checks before publishing")
        try expect(source.contains("Scripts/build-release.sh"), "release workflow should build the release artifact")
        try expect(source.contains("repository: kwiats/switch-commit-release-channel"), "release workflow should checkout the public release channel")
        try expect(source.contains("RELEASE_CHANNEL_TOKEN"), "release workflow should use a token scoped to the public release channel")
        try expect(source.contains("SPARKLE_PRIVATE_ED_KEY"), "release workflow should provide Sparkle signing material only from secrets")
        try expect(source.contains("GH_TOKEN: ${{ secrets.RELEASE_CHANNEL_TOKEN }}"), "release workflow should authenticate gh release against the channel repo")
        try expect(source.contains("Scripts/publish-release-channel.sh"), "release workflow should publish through the checked-in publisher script")
        try expect(source.contains("git push"), "release workflow should push the release channel update")
    }),
    ("README documents tag release CD and release channel secrets", {
        let readmeURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("README.md")
        let source = try String(contentsOf: readmeURL, encoding: .utf8)

        try expect(source.contains("git tag v0.2.0"), "README should show how to tag a release")
        try expect(source.contains("RELEASE_CHANNEL_TOKEN"), "README should document the release channel token secret")
        try expect(source.contains("SPARKLE_PRIVATE_ED_KEY"), "README should document the Sparkle private key secret")
        try expect(source.contains("generate_keys -x /tmp/sparkle-private-key.txt"), "README should show how to export the Sparkle private key")
        try expect(source.contains("Do not use the public SUPublicEDKey value"), "README should warn against using the public key as the private secret")
        try expect(source.contains("https://kwiats.github.io/switch-commit-release-channel/appcast.xml"), "README should document the public appcast URL")
        try expect(source.contains("version.txt"), "README should document the Pages version marker")
        try expect(source.contains("docs/release-channel/index.html"), "README should document the landing template")
        try expect(
            source.contains("https://github.com/kwiats/switch-commit-release-channel/releases/download/"),
            "README should document GitHub Releases download URLs"
        )
        try expect(source.contains("SwitchCommit-v"), "README should document SwitchCommit DMG artifact naming")
        try expect(source.contains("macOS.dmg"), "README should document DMG release artifacts")
        try expect(source.contains("swift run SwitchCommitCoreTestRunner"), "README should document the renamed test runner")
        try expect(!source.contains("macOS.zip"), "README should not document ZIP release artifacts")
    }),
    ("menu bar app omits diagnostics shortcut and uses Switch Commit chrome", {
        let appURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SwitchCommitApp/SwitchCommitApp.swift")
        let windowURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SwitchCommitApp/SettingsWindowController.swift")
        let appSource = try String(contentsOf: appURL, encoding: .utf8)
        let windowSource = try String(contentsOf: windowURL, encoding: .utf8)

        try expect(!appSource.contains("Run Local Diagnostics"), "menu should not expose the local diagnostics shortcut")
        try expect(!appSource.contains("#selector(runLocalDiagnostics)"), "menu should not wire a diagnostics menu action")
        try expect(appSource.contains("accessibilityDescription: \"Switch Commit\""), "status item should use Switch Commit in app chrome")
        try expect(windowSource.contains("createdWindow.title = \"Switch Commit Settings\""), "settings window header should use Switch Commit")
    }),
    ("run local diagnostics requests settings presentation", {
        try MainActor.assumeIsolated {
            let viewModel = AppViewModel(profiles: [])
            viewModel.runLocalDiagnostics()
            try expect(
                viewModel.presentationRequest == .settings,
                "diagnostics should request visible settings presentation"
            )
            try expect(
                viewModel.diagnosticsText.contains("No network checks run automatically"),
                "diagnostics should explain that it stays local"
            )
        }
    }),
    ("settings action requests settings presentation", {
        try MainActor.assumeIsolated {
            let viewModel = AppViewModel(profiles: [])
            viewModel.requestSettingsPresentation()
            try expect(
                viewModel.presentationRequest == .settings,
                "settings action should request visible settings presentation"
            )
        }
    }),
    ("app view model initializes launch at login from manager status", {
        try MainActor.assumeIsolated {
            let launchAtLoginManager = FakeLaunchAtLoginManager(status: .enabled)
            let viewModel = AppViewModel(
                profiles: [],
                launchAtLoginManager: launchAtLoginManager
            )

            try expect(viewModel.isLaunchAtLoginEnabled, "enabled manager status should enable settings toggle")
            try expect(
                viewModel.launchAtLoginStatusText == "Launch at login is enabled.",
                "view model should expose enabled launch-at-login status text"
            )
        }
    }),
    ("app view model enables launch at login through manager", {
        try MainActor.assumeIsolated {
            let launchAtLoginManager = FakeLaunchAtLoginManager(status: .disabled)
            let viewModel = AppViewModel(
                profiles: [],
                launchAtLoginManager: launchAtLoginManager
            )

            viewModel.setLaunchAtLoginEnabled(true)

            try expect(launchAtLoginManager.enableCallCount == 1, "enable should register launch at login")
            try expect(viewModel.isLaunchAtLoginEnabled, "successful enable should update settings toggle")
            try expect(
                viewModel.launchAtLoginStatusText == "Launch at login is enabled.",
                "successful enable should expose enabled status text"
            )
        }
    }),
    ("app view model disables launch at login through manager", {
        try MainActor.assumeIsolated {
            let launchAtLoginManager = FakeLaunchAtLoginManager(status: .enabled)
            let viewModel = AppViewModel(
                profiles: [],
                launchAtLoginManager: launchAtLoginManager
            )

            viewModel.setLaunchAtLoginEnabled(false)

            try expect(launchAtLoginManager.disableCallCount == 1, "disable should unregister launch at login")
            try expect(!viewModel.isLaunchAtLoginEnabled, "successful disable should update settings toggle")
            try expect(
                viewModel.launchAtLoginStatusText == "Launch at login is disabled.",
                "successful disable should expose disabled status text"
            )
        }
    }),
    ("app view model reverts launch at login setting after manager failure", {
        try MainActor.assumeIsolated {
            let launchAtLoginManager = FakeLaunchAtLoginManager(status: .disabled)
            launchAtLoginManager.errorToThrow = FakeLaunchAtLoginError.denied
            let viewModel = AppViewModel(
                profiles: [],
                launchAtLoginManager: launchAtLoginManager
            )

            viewModel.setLaunchAtLoginEnabled(true)

            try expect(!viewModel.isLaunchAtLoginEnabled, "failed enable should refresh toggle from manager status")
            try expect(
                viewModel.launchAtLoginStatusText.contains("Could not update launch at login"),
                "failed enable should expose error text"
            )
        }
    }),
    ("adding an account requests menu content rebuild", {
        try MainActor.assumeIsolated {
            let viewModel = AppViewModel(profiles: [])
            let initialRevision = viewModel.menuContentRevision

            viewModel.addProfile()

            try expect(viewModel.profiles.count == 1, "add profile should update app-facing profiles")
            try expect(
                viewModel.menuContentRevision == initialRevision + 1,
                "profile mutations should request menu content rebuild"
            )
        }
    }),
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
    }),
    ("menu content rebuild signal sees added profile immediately", {
        try MainActor.assumeIsolated {
            let viewModel = AppViewModel(profiles: [])
            var profileCountAtRebuild: Int?
            let cancellable = viewModel.$menuContentRevision
                .dropFirst()
                .sink { _ in
                    profileCountAtRebuild = viewModel.profiles.count
                }

            viewModel.addProfile()
            cancellable.cancel()

            try expect(
                profileCountAtRebuild == 1,
                "menu rebuild observer should see the newly added profile immediately"
            )
        }
    }),
    ("https profile reports neutral credential status", {
        try MainActor.assumeIsolated {
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
            let viewModel = AppViewModel(profiles: [profile])

            let status = viewModel.connectionStatus(for: profile)

            try expect(status.message == "Uses HTTPS credentials.", "https status should not ask for ssh")
            try expect(status.displayColorName == "green", "https profile should be locally complete")
        }
    }),
    ("app view model connection status starts red and turns green after manual test", {
        final class SuccessfulConnectionRunner: CommandRunning {
            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                CommandResult(exitCode: 0, standardOutput: "connected", standardError: "")
            }
        }

        try MainActor.assumeIsolated {
            let profile = try GitProfile(
                id: "personal",
                displayName: "Personal",
                gitUserName: "Personal User",
                gitUserEmail: "me@example.com",
                sshKeyPath: "~/.ssh/id_ed25519",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
            let viewModel = AppViewModel(
                profiles: [profile],
                diagnosticsService: DiagnosticsService(commandRunner: SuccessfulConnectionRunner())
            )

            try expect(
                viewModel.connectionStatus(for: profile).displayColorName == "red",
                "untested profile should be red"
            )

            viewModel.testConnectionForSelectedProfile()
            try expect(
                waitUntil { viewModel.connectionStatus(for: profile).displayColorName == "green" },
                "successful manual test should turn status green"
            )
        }
    }),
    ("app view model persists manual connection status across restart", {
        final class SuccessfulConnectionRunner: CommandRunning {
            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                CommandResult(exitCode: 0, standardOutput: "connected", standardError: "")
            }
        }

        try MainActor.assumeIsolated {
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
            let store = ProfileStore(fileURL: storeURL)
            let profile = try GitProfile(
                id: "persistent",
                displayName: "Persistent",
                gitUserName: "Persistent User",
                gitUserEmail: "persistent@example.com",
                sshKeyPath: "~/.ssh/id_persistent",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
            let firstViewModel = AppViewModel(
                profiles: [profile],
                profileStore: store,
                diagnosticsService: DiagnosticsService(commandRunner: SuccessfulConnectionRunner())
            )

            firstViewModel.testConnectionForSelectedProfile()
            try expect(
                waitUntil { firstViewModel.connectionStatus(for: profile).displayColorName == "green" },
                "manual test should turn status green before restart"
            )

            let reloadedViewModel = AppViewModel(
                profiles: [],
                profileStore: store,
                diagnosticsService: DiagnosticsService(commandRunner: SuccessfulConnectionRunner())
            )
            guard let reloadedProfile = reloadedViewModel.profiles.first(where: { $0.id == "persistent" }) else {
                throw TestFailure.expectationFailed("reloaded profile should exist")
            }

            try expect(
                reloadedViewModel.connectionStatus(for: reloadedProfile).displayColorName == "green",
                "persisted manual test should survive a new view model"
            )
            let loaded = try ProfileStore(fileURL: storeURL).load()
            try expect(
                loaded.profileConnectionStates["persistent"]?.results.first?.message == "connected",
                "manual test result should be written to profile store"
            )
        }
    }),
    ("app view model automatically tests switched ssh profile and persists result", {
        final class RecordingSuccessfulConnectionRunner: CommandRunning {
            var hosts: [String] = []

            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                hosts.append(arguments.last ?? "")
                return CommandResult(exitCode: 0, standardOutput: "auto connected", standardError: "")
            }
        }

        try MainActor.assumeIsolated {
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
            let store = ProfileStore(fileURL: storeURL)
            let personal = try GitProfile(
                id: "personal",
                displayName: "Personal",
                gitUserName: "Personal User",
                gitUserEmail: "me@example.com",
                sshKeyPath: "~/.ssh/id_personal",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
            let work = try GitProfile(
                id: "work",
                displayName: "Work",
                gitUserName: "Work User",
                gitUserEmail: "work@example.com",
                sshKeyPath: "~/.ssh/id_work",
                hosts: ["gitlab.com"],
                httpsCredentialRef: nil,
                isDefault: false
            )
            let runner = RecordingSuccessfulConnectionRunner()
            let viewModel = AppViewModel(
                profiles: [personal, work],
                profileStore: store,
                diagnosticsService: DiagnosticsService(commandRunner: runner)
            )

            viewModel.switchGlobalProfile(to: work)

            try expect(
                waitUntil {
                    let loaded = (try? ProfileStore(fileURL: storeURL).load())
                    return loaded?.profileConnectionStates["work"]?.results.first?.message == "auto connected"
                },
                "switching global profile should persist an automatic connection result"
            )
            try expect(
                viewModel.selectedProfileId == "personal",
                "switching global profile from menu should not require selected settings profile to change"
            )
            try expect(
                viewModel.connectionStatus(for: work).displayColorName == "green",
                "automatic connection result should update switched profile status"
            )
            try expect(
                runner.hosts.contains("git@gitlab.com"),
                "automatic test should run against the switched profile host"
            )
        }
    }),
    ("app view model clears ssh connection status after access method changes", {
        final class SuccessfulConnectionRunner: CommandRunning {
            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                CommandResult(exitCode: 0, standardOutput: "connected", standardError: "")
            }
        }

        try MainActor.assumeIsolated {
            let profile = try GitProfile(
                id: "switching",
                displayName: "Switching",
                gitUserName: "Switching User",
                gitUserEmail: "switching@example.com",
                sshKeyPath: "~/.ssh/id_switching",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
            let viewModel = AppViewModel(
                profiles: [profile],
                diagnosticsService: DiagnosticsService(commandRunner: SuccessfulConnectionRunner())
            )

            viewModel.testConnectionForSelectedProfile()
            try expect(
                waitUntil { viewModel.connectionStatus(for: profile).displayColorName == "green" },
                "successful manual test should turn status green before access changes"
            )

            viewModel.updateSelectedProfileAccessMethod(.https)
            viewModel.updateSelectedProfileAccessMethod(.ssh)

            guard let selectedProfile = viewModel.selectedProfile else {
                throw TestFailure.expectationFailed("selected profile should still exist after access changes")
            }
            let status = viewModel.connectionStatus(for: selectedProfile)
            try expect(status.message == "Connection not tested.", "switching back to ssh should require a fresh test")
            try expect(status.displayColorName == "red", "switching back to ssh should not keep stale green status")
        }
    }),
    ("app view model discards in-flight ssh test results after switching to https", {
        final class DelayedSuccessfulConnectionRunner: CommandRunning {
            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                Thread.sleep(forTimeInterval: 0.15)
                return CommandResult(exitCode: 0, standardOutput: "connected", standardError: "")
            }
        }

        try MainActor.assumeIsolated {
            let profile = try GitProfile(
                id: "delayed-switch",
                displayName: "Delayed Switch",
                gitUserName: "Delayed User",
                gitUserEmail: "delayed@example.com",
                sshKeyPath: "~/.ssh/id_delayed",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
            let viewModel = AppViewModel(
                profiles: [profile],
                diagnosticsService: DiagnosticsService(commandRunner: DelayedSuccessfulConnectionRunner())
            )

            viewModel.testConnectionForSelectedProfile()
            viewModel.updateSelectedProfileAccessMethod(.https)
            viewModel.testConnectionForSelectedProfile()

            try expect(
                viewModel.settingsMessage == "HTTPS access uses Git credentials.",
                "https no-op should set credential status message"
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            try expect(
                viewModel.settingsMessage == "HTTPS access uses Git credentials.",
                "in-flight ssh test should not overwrite https status message"
            )

            viewModel.updateSelectedProfileAccessMethod(.ssh)
            guard let selectedProfile = viewModel.selectedProfile else {
                throw TestFailure.expectationFailed("selected profile should still exist after switching back to ssh")
            }
            let status = viewModel.connectionStatus(for: selectedProfile)
            try expect(status.message == "Connection not tested.", "discarded in-flight result should not become stale ssh status")
            try expect(status.displayColorName == "red", "discarded in-flight result should not turn ssh status green")
        }
    }),
    ("app view model connection status turns orange after failed manual test", {
        final class FailedConnectionRunner: CommandRunning {
            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                CommandResult(exitCode: 255, standardOutput: "", standardError: "Permission denied (publickey).")
            }
        }

        try MainActor.assumeIsolated {
            let profile = try GitProfile(
                id: "work",
                displayName: "Work",
                gitUserName: "Work User",
                gitUserEmail: "work@example.com",
                sshKeyPath: "~/.ssh/id_work",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
            let viewModel = AppViewModel(
                profiles: [profile],
                diagnosticsService: DiagnosticsService(commandRunner: FailedConnectionRunner())
            )

            viewModel.testConnectionForSelectedProfile()

            try expect(
                waitUntil { viewModel.connectionStatus(for: profile).displayColorName == "orange" },
                "failed manual test should turn status orange"
            )
            try expect(
                viewModel.connectionStatus(for: profile).message.contains("Permission denied"),
                "failed manual test should expose SSH failure message"
            )
        }
    }),
    ("profile git binding status exposes manual connection status for menu icons", {
        try MainActor.assumeIsolated {
            let profile = try GitProfile(
                id: "personal",
                displayName: "Personal",
                gitUserName: "Personal User",
                gitUserEmail: "me@example.com",
                sshKeyPath: "~/.ssh/id_ed25519",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
            let viewModel = AppViewModel(profiles: [profile])

            try expect(
                viewModel.gitBindingStatus(for: profile).systemImageName == "circle.fill",
                "manual connection status should expose a menu icon"
            )
            try expect(
                viewModel.gitBindingStatus(for: profile).displayColorName == "red",
                "untested connection status should be red"
            )
        }
    }),
    ("app view model exposes provider icon metadata for account rows", {
        try MainActor.assumeIsolated {
            let githubProfile = try GitProfile(
                id: "personal",
                displayName: "Personal",
                gitUserName: "Personal User",
                gitUserEmail: "me@example.com",
                sshKeyPath: "~/.ssh/id_ed25519",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
            let genericProfile = try GitProfile(
                id: "gitlab",
                displayName: "GitLab",
                gitUserName: "GitLab User",
                gitUserEmail: "gitlab@example.com",
                sshKeyPath: "~/.ssh/id_gitlab",
                hosts: ["gitlab.com"],
                httpsCredentialRef: nil,
                isDefault: false
            )
            let viewModel = AppViewModel(profiles: [githubProfile, genericProfile])

            try expect(
                viewModel.providerSystemImageName(for: githubProfile) == "person.crop.circle.badge.checkmark",
                "github profile should expose provider icon"
            )
            try expect(
                viewModel.providerSystemImageName(for: genericProfile) == "terminal",
                "non-github profile should expose generic git provider icon"
            )
            try expect(
                viewModel.connectionStatus(for: githubProfile).systemImageName == "circle.fill",
                "status should expose dot icon"
            )
        }
    })
]

var failures: [String] = []

for (name, test) in tests {
    do {
        try test()
        print("PASS \(name)")
    } catch {
        failures.append("FAIL \(name): \(error)")
    }
}

if failures.isEmpty {
    print("All \(tests.count) tests passed.")
} else {
    failures.forEach { print($0) }
    exit(1)
}
