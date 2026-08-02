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

enum FakeCLIInstallerError: Error {
    case denied
}

final class FakeCLIInstaller: CLIInstalling, @unchecked Sendable {
    var statusMessage: String
    var installCallCount = 0
    var errorToThrow: Error?

    init(statusMessage: String) {
        self.statusMessage = statusMessage
    }

    func installOrRepair() throws {
        installCallCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
    }

    func installOrRepair(allowAdministrator: Bool) throws {
        _ = allowAdministrator
        try installOrRepair()
    }
}

let tests: [(String, () throws -> Void)] = [
    ("CLI version reads the packaged app version and emits JSON", {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("switch-commit-version-\(UUID().uuidString)")
        let executable = temporaryDirectory
            .appendingPathComponent("Switch Commit.app/Contents/MacOS/switch-commit")
        let infoPlist = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Info.plist")

        try fileManager.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>CFBundleShortVersionString</key><string>1.2.3</string>
        </dict></plist>
        """.write(to: infoPlist, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        try expect(
            CLIVersion.current(executableURL: executable, environment: [:]) == "1.2.3",
            "CLI version should read CFBundleShortVersionString from its app bundle"
        )
        try expect(
            CLIOutput.jsonVersion(CLIVersion.current(executableURL: executable, environment: [:]))
                == "{\"ok\":true,\"version\":\"1.2.3\"}",
            "CLI version JSON should include a successful version response"
        )
    }),
    ("version comparator orders dotted releases", {
        try expect(VersionComparator.isNewer("0.3.5", than: "0.3.4"), "0.3.5 should be newer than 0.3.4")
        try expect(!VersionComparator.isNewer("0.3.4", than: "0.3.5"), "0.3.4 should not be newer than 0.3.5")
        try expect(VersionComparator.isNewer("0.3.5", than: "0.3.5-dev"), "release should beat -dev suffix")
        try expect(VersionComparator.compare("1.0.0", "1.0.0") == .orderedSame, "equal versions compare equal")
    }),
    ("insteadOf remediator removes unmanaged HTTPS rewrite opposing SSH profile", {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("insteadOf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent(".gitconfig")
        try """
        [url "https://github.com/"]
            insteadOf = git@github.com:
        [include]
            path = ~/.config/git-account-switcher/global.gitconfig

        """.write(to: root, atomically: true, encoding: .utf8)

        let profile = try GitProfile(
            id: "private",
            displayName: "Private",
            gitUserName: "me",
            gitUserEmail: "me@example.com",
            accessMethod: .ssh,
            sshKeyPath: "~/.ssh/id",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let remediator = InsteadOfConflictRemediator(homeDirectory: home)
        let entries = remediator.parseRootGitConfig(try String(contentsOf: root, encoding: .utf8), originPath: root.path)
        let result = try remediator.remediate(
            entries: entries,
            activeProfile: profile,
            rootGitConfigURL: root,
            backup: { _ in }
        )
        try expect(result.removed.count == 1, "should remove one conflicting insteadOf")
        let updated = try String(contentsOf: root, encoding: .utf8)
        try expect(!updated.lowercased().contains("insteadof = git@github.com:"), "conflicting insteadOf should be gone")
        try expect(updated.contains("git-account-switcher/global.gitconfig"), "include lines must remain")
    }),
    ("release channel appcast parser reads newest enclosure", {
        let xml = """
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <title>0.3.5</title>
              <sparkle:shortVersionString>0.3.5</sparkle:shortVersionString>
              <enclosure url="https://example.com/SwitchCommit-v0.3.5-macOS.dmg" length="1" type="application/octet-stream"/>
            </item>
            <item>
              <title>0.3.4</title>
              <sparkle:shortVersionString>0.3.4</sparkle:shortVersionString>
              <enclosure url="https://example.com/SwitchCommit-v0.3.4-macOS.dmg" length="1" type="application/octet-stream"/>
            </item>
          </channel>
        </rss>
        """
        let parsed = try ReleaseChannelUpdateService.parseAppcast(xml)
        try expect(parsed.version == "0.3.5", "parser should use first/newest item version")
        try expect(parsed.enclosureURL.absoluteString.contains("0.3.5"), "parser should use newest enclosure")
    }),
    ("CLI version uses environment override then development fallback", {
        let executable = URL(fileURLWithPath: "/tmp/switch-commit")

        try expect(
            CLIVersion.current(
                executableURL: executable,
                environment: ["SWITCH_COMMIT_VERSION": "2.0.0"]
            ) == "2.0.0",
            "CLI version should prefer an explicit release environment override"
        )
        try expect(
            CLIVersion.current(executableURL: executable, environment: [:]) == "0.3.0-dev",
            "CLI version should use the development fallback outside an app bundle"
        )
    }),
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
    ("folder rule resolver normalize expands tilde and strips trailing slash", {
        let home = URL(fileURLWithPath: "/Users/demo")
        try expect(
            FolderRuleResolver.normalize("~/Dev/", homeDirectory: home) == "/Users/demo/Dev",
            "tilde and trailing slash should normalize"
        )
        try expect(
            FolderRuleResolver.normalize("/Users/demo/Dev/", homeDirectory: home) == "/Users/demo/Dev",
            "trailing slash should strip"
        )
        try expect(
            FolderRuleResolver.normalize("/", homeDirectory: home) == "/",
            "root should stay root"
        )
    }),
    ("folder rule resolver normalize resolves relative paths against current directory", {
        let home = URL(fileURLWithPath: "/Users/demo")
        let cwd = URL(fileURLWithPath: "/Users/demo/switch-commit")
        try expect(
            FolderRuleResolver.normalize(".", homeDirectory: home, currentDirectory: cwd)
                == "/Users/demo/switch-commit",
            "dot should resolve to current directory"
        )
        try expect(
            FolderRuleResolver.normalize("./repo", homeDirectory: home, currentDirectory: cwd)
                == "/Users/demo/switch-commit/repo",
            "relative repo path should resolve against current directory"
        )
        try expect(
            FolderRuleResolver.normalize("repo/", homeDirectory: home, currentDirectory: cwd)
                == "/Users/demo/switch-commit/repo",
            "relative path with trailing slash should resolve and strip slash"
        )
    }),
    ("profile settings manager resolves relative folder rule paths to absolute gitdir patterns", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoDirectory = temporaryDirectory.appendingPathComponent("switch-commit", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDirectory, withIntermediateDirectories: true)
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
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: temporaryDirectory.appendingPathComponent("profiles.json")),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [profile],
            gitConfigInstaller: ManagedGitConfigInstaller(homeDirectory: temporaryDirectory),
            homeDirectory: temporaryDirectory
        )
        let previousDirectory = FileManager.default.currentDirectoryPath
        defer { _ = FileManager.default.changeCurrentDirectoryPath(previousDirectory) }
        guard FileManager.default.changeCurrentDirectoryPath(repoDirectory.path) else {
            throw TestFailure.expectationFailed("unable to enter temporary repo directory")
        }

        let rule = try manager.addFolderRule(path: ".", profileId: "work", matchMode: .singleRepo)

        try expect(rule.path == repoDirectory.path, "relative dot path should become absolute")
        let rulesConfig = try String(
            contentsOf: temporaryDirectory.appendingPathComponent(".config/git-account-switcher/rules.gitconfig"),
            encoding: .utf8
        )
        try expect(
            rulesConfig.contains("[includeIf \"gitdir:\(repoDirectory.path)/\"]"),
            "single-repo rule should emit absolute gitdir pattern"
        )
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
            sshCommand = ssh -i '~/.ssh/id_work'
        [url "git@github.com:"]
            insteadOf = https://github.com/
            insteadOf = ssh://git@github.com/

        """
        try expect(profileConfig == expectedProfileConfig, "ssh profile config should remain byte stable")
        try expect(profileConfig.contains("[user]"), "profile config should contain user section")
        try expect(profileConfig.contains("name = Work User"), "profile config should contain name")
        try expect(profileConfig.contains("email = work@example.com"), "profile config should contain email")
        try expect(profileConfig.contains("sshCommand = ssh -i '~/.ssh/id_work'"), "profile config should contain ssh command")
        try expect(!profileConfig.contains("-F ~/.ssh/config"), "sshCommand must not require ~/.ssh/config via -F")
        try expect(profileConfig.contains("[url \"git@github.com:\"]"), "ssh profile should rewrite URLs to SSH")
        try expect(profileConfig.contains("insteadOf = https://github.com/"), "ssh profile should rewrite HTTPS remotes")
        try expect(profileConfig.contains("insteadOf = ssh://git@github.com/"), "ssh profile should normalize ssh URL form")

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
        try expect(config.contains("sshCommand = ssh -i '/Users/me/My Keys/id_work'\\''; env'"), "ssh key path should be shell quoted")
        try expect(!config.contains("-F ~/.ssh/config"), "quoted sshCommand must not require -F ~/.ssh/config")
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
        let expected = """
        [user]
            name = Personal User
            email = me@example.com
        [url "https://github.com/"]
            insteadOf = git@github.com:
            insteadOf = ssh://git@github.com/

        """

        try expect(config == expected, "https profile config should remain byte stable")
        try expect(config.contains("[user]"), "https profile config should include user section")
        try expect(config.contains("name = Personal User"), "https profile config should include git name")
        try expect(config.contains("email = me@example.com"), "https profile config should include git email")
        try expect(!config.contains("[core]"), "https profile config should not include core section")
        try expect(!config.contains("sshCommand"), "https profile config should not include ssh command")
        try expect(config.contains("[url \"https://github.com/\"]"), "https profile should rewrite URLs to HTTPS")
        try expect(config.contains("insteadOf = git@github.com:"), "https profile should rewrite SSH remotes")
    }),
    ("git config generator emits insteadOf for each profile host", {
        let profile = try GitProfile(
            id: "multi",
            displayName: "Multi",
            gitUserName: "Multi User",
            gitUserEmail: "multi@example.com",
            sshKeyPath: "~/.ssh/id_multi",
            hosts: ["github.com", "gitlab.com"],
            httpsCredentialRef: nil,
            isDefault: false
        )
        let config = GitConfigGenerator().profileConfig(for: profile)
        try expect(config.contains("[url \"git@github.com:\"]"), "should rewrite github.com")
        try expect(config.contains("[url \"git@gitlab.com:\"]"), "should rewrite gitlab.com")
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
    ("ssh key discovery lists private keys and skips junk", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sshDirectory = temporaryDirectory.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: sshDirectory.appendingPathComponent("id_ed25519"))
        try Data("private".utf8).write(to: sshDirectory.appendingPathComponent("id_rsa"))
        try Data("public".utf8).write(to: sshDirectory.appendingPathComponent("id_ed25519.pub"))
        try Data("config".utf8).write(to: sshDirectory.appendingPathComponent("config"))
        try Data("hosts".utf8).write(to: sshDirectory.appendingPathComponent("known_hosts"))
        try Data("auth".utf8).write(to: sshDirectory.appendingPathComponent("authorized_keys"))
        try FileManager.default.createDirectory(
            at: sshDirectory.appendingPathComponent("somedir", isDirectory: true),
            withIntermediateDirectories: true
        )

        let paths = SSHKeyDiscovery(homeDirectory: temporaryDirectory).discoverKeyPaths()
        try expect(paths == ["~/.ssh/id_ed25519", "~/.ssh/id_rsa"], "should list private keys sorted by basename")
    }),
    ("ssh key discovery includes IdentityFile paths from config and managed include", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sshDirectory = temporaryDirectory.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: sshDirectory.appendingPathComponent("id_ed25519"))
        try """
        Host github.com
            IdentityFile ~/.ssh/id_ed25519
            IdentityFile ~/.ssh/id_work
        """.write(to: sshDirectory.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        try Data("private".utf8).write(to: sshDirectory.appendingPathComponent("id_work"))
        try """
        Host gitlab.com
            IdentityFile ~/.ssh/id_gitlab
        """.write(
            to: sshDirectory.appendingPathComponent("git-account-switcher.conf"),
            atomically: true,
            encoding: .utf8
        )
        try Data("private".utf8).write(to: sshDirectory.appendingPathComponent("id_gitlab"))

        let paths = SSHKeyDiscovery(homeDirectory: temporaryDirectory).discoverKeyPaths()
        try expect(
            paths == ["~/.ssh/id_ed25519", "~/.ssh/id_gitlab", "~/.ssh/id_work"],
            "should merge directory keys and IdentityFile entries with stable dedup/sort"
        )
    }),
    ("ssh key discovery returns empty list when ssh directory is missing", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = SSHKeyDiscovery(homeDirectory: temporaryDirectory).discoverKeyPaths()
        try expect(paths.isEmpty, "missing .ssh should yield empty list")
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
    ("safe file writer concurrent overwrites create unique backups without error", {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let writer = SafeFileWriter(allowedRoots: [managed], backupDirectory: backups)
        let target = managed.appendingPathComponent("global.gitconfig")

        try writer.write("seed", to: target)

        let group = DispatchGroup()
        let lock = NSLock()
        var failures: [String] = []
        let writerCount = 24
        for index in 0..<writerCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                do {
                    try writer.write("content-\(index)", to: target)
                } catch {
                    lock.lock()
                    failures.append(String(describing: error))
                    lock.unlock()
                }
            }
        }
        group.wait()

        try expect(
            failures.isEmpty,
            "concurrent managed writes should not collide on backup names: \(failures.prefix(3).joined(separator: "; "))"
        )
        let backupFiles = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        try expect(backupFiles.count == writerCount, "each overwrite should create its own backup")
        try expect(
            Set(backupFiles).count == backupFiles.count,
            "backup filenames must be unique under concurrency"
        )
        try expect(
            backupFiles.allSatisfy { $0.contains("global.gitconfig") },
            "backups should retain original filename suffix"
        )
    }),
    ("safe file writer skips backup when content is unchanged", {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let writer = SafeFileWriter(allowedRoots: [managed], backupDirectory: backups)
        let target = managed.appendingPathComponent("global.gitconfig")

        try writer.write("unchanged", to: target)
        try writer.write("unchanged", to: target)

        let backupFiles: [String]
        if FileManager.default.fileExists(atPath: backups.path) {
            backupFiles = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        } else {
            backupFiles = []
        }
        try expect(backupFiles.isEmpty, "identical rewrite should not create a backup")
        let content = try String(contentsOf: target, encoding: .utf8)
        try expect(content == "unchanged", "identical rewrite should leave managed content intact")
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
        let keyedCommand = service.sshConnectionTestCommand(
            host: "github.com",
            identityFile: "~/.ssh/id_ed25519_work"
        )

        try expect(githubCommand.command == "ssh", "github command should use ssh")
        try expect(
            githubCommand.arguments == ["-o", "BatchMode=yes", "-T", "git@github.com"],
            "github command without identity should use default agent keys"
        )
        try expect(gitlabCommand.command == "ssh", "generic host command should use ssh")
        try expect(
            gitlabCommand.arguments == ["-o", "BatchMode=yes", "-T", "git@gitlab.com"],
            "generic host command without identity should use default agent keys"
        )
        try expect(keyedCommand.command == "ssh", "keyed command should use ssh")
        try expect(
            keyedCommand.arguments == [
                "-o", "BatchMode=yes",
                "-o", "IdentitiesOnly=yes",
                "-i", "~/.ssh/id_ed25519_work",
                "-T", "git@github.com"
            ],
            "keyed command should force the profile identity file"
        )
    }),
    ("diagnostics testSSHConnection passes identity file to the runner", {
        final class RecordingRunner: CommandRunning {
            var arguments: [String] = []

            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                self.arguments = arguments
                return CommandResult(
                    exitCode: 1,
                    standardOutput: "",
                    standardError: "Hi work! You've successfully authenticated, but GitHub does not provide shell access."
                )
            }
        }

        let runner = RecordingRunner()
        let result = DiagnosticsService(commandRunner: runner).testSSHConnection(
            host: "github.com",
            identityFile: "~/.ssh/id_work"
        )

        try expect(result.status == .connected, "keyed github auth should count as connected")
        try expect(runner.arguments.contains("-i"), "connection test should pass -i")
        try expect(runner.arguments.contains("~/.ssh/id_work"), "connection test should pass identity path")
        try expect(runner.arguments.contains("IdentitiesOnly=yes"), "connection test should force IdentitiesOnly")
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
    ("switch commit session lists profiles and switches active", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let personal = try GitProfile(
            id: "personal",
            displayName: "Personal",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com",
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
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: false
        )
        let store = ProfileStore(fileURL: temporaryDirectory.appendingPathComponent("profiles.json"))
        try store.save(ProfileStoreData(profiles: [personal, work]))
        let session = try SwitchCommitSession(
            profileStore: store,
            keychainStore: InMemoryKeychainStore(),
            gitConfigInstaller: ManagedGitConfigInstaller(homeDirectory: temporaryDirectory),
            homeDirectory: temporaryDirectory
        )

        try expect(session.profiles == [personal, work], "session should expose persisted profiles")
        try session.use(reference: "Work")

        try expect(session.activeProfile?.id == "work", "use should resolve a display name and switch active profile")
        let globalConfig = try String(
            contentsOf: temporaryDirectory.appendingPathComponent(".config/git-account-switcher/global.gitconfig"),
            encoding: .utf8
        )
        try expect(globalConfig.contains("name = Work User"), "use should update managed global config")
    }),
    ("switch commit session status reports folder context", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let personal = try GitProfile(
            id: "personal",
            displayName: "Personal",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com",
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
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: false
        )
        let projectPath = temporaryDirectory.appendingPathComponent("Dev/project").path
        let rule = try FolderRule(
            id: "work-dev",
            path: temporaryDirectory.appendingPathComponent("Dev").path,
            profileId: "work",
            matchMode: .folderTree,
            enabled: true
        )
        let store = ProfileStore(fileURL: temporaryDirectory.appendingPathComponent("profiles.json"))
        try store.save(ProfileStoreData(profiles: [personal, work], rules: [rule]))
        let session = try SwitchCommitSession(
            profileStore: store,
            keychainStore: InMemoryKeychainStore(),
            gitConfigInstaller: nil,
            homeDirectory: temporaryDirectory
        )

        let status = session.status(path: projectPath)

        try expect(status.activeProfile?.id == "personal", "status should retain the active global profile")
        try expect(status.contextSource == .folder, "matching rule should report folder context")
        try expect(status.contextProfile?.id == "work", "matching rule should select its profile")
        try expect(status.contextPath == projectPath, "status should report the inspected path")
    }),
    ("switch commit session uses its home directory for folder rules", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let work = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            sshKeyPath: "~/.ssh/id_work",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let store = ProfileStore(fileURL: temporaryDirectory.appendingPathComponent("profiles.json"))
        try store.save(ProfileStoreData(profiles: [work]))
        let session = try SwitchCommitSession(
            profileStore: store,
            keychainStore: InMemoryKeychainStore(),
            gitConfigInstaller: nil,
            homeDirectory: temporaryDirectory
        )

        let rule = try session.addFolderRule(path: "~/Dev", profileReference: "work")
        try expect(
            rule.path == temporaryDirectory.appendingPathComponent("Dev").path,
            "folder rules should expand tilde relative to the session home directory"
        )
        try session.removeFolderRule(path: "~/Dev")
        try expect(session.rules.isEmpty, "folder rule removal should use the session home directory")
    }),
    ("switch commit session doctor uses local git configuration only", {
        final class RecordingRunner: CommandRunning {
            var invocations: [(command: String, arguments: [String])] = []

            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                invocations.append((command, arguments))
                return CommandResult(exitCode: 0, standardOutput: "file\tvalue", standardError: "")
            }
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runner = RecordingRunner()
        let session = try SwitchCommitSession(
            profileStore: ProfileStore(fileURL: temporaryDirectory.appendingPathComponent("profiles.json")),
            keychainStore: InMemoryKeychainStore(),
            gitConfigInstaller: nil,
            homeDirectory: temporaryDirectory,
            commandRunner: runner
        )

        _ = session.doctor(path: temporaryDirectory.path)

        try expect(runner.invocations.count == 3, "doctor should inspect three git configuration values")
        try expect(runner.invocations.allSatisfy { $0.command == "git" }, "doctor should only invoke git")
        try expect(
            runner.invocations.allSatisfy { $0.arguments.first == "config" },
            "doctor should only invoke git config commands"
        )
        try expect(
            !runner.invocations.contains { $0.command == "ssh" },
            "doctor must not invoke SSH diagnostics"
        )
    }),
    ("switch commit session doctor warns when folder and global access methods conflict", {
        final class QuietRunner: CommandRunning {
            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                CommandResult(exitCode: 0, standardOutput: "file\tvalue", standardError: "")
            }
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let personal = try GitProfile(
            id: "personal",
            displayName: "Personal",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com",
            accessMethod: .https,
            sshKeyPath: "",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let work = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            accessMethod: .ssh,
            sshKeyPath: "~/.ssh/id_work",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: false
        )
        let projectPath = temporaryDirectory.appendingPathComponent("Projects/Acme").path
        let store = ProfileStore(fileURL: temporaryDirectory.appendingPathComponent("profiles.json"))
        try store.save(ProfileStoreData(
            profiles: [personal, work],
            rules: [
                try FolderRule(
                    id: "work-folder",
                    path: projectPath,
                    profileId: "work",
                    matchMode: .folderTree,
                    enabled: true
                )
            ]
        ))
        let session = try SwitchCommitSession(
            profileStore: store,
            keychainStore: InMemoryKeychainStore(),
            gitConfigInstaller: nil,
            homeDirectory: temporaryDirectory,
            commandRunner: QuietRunner()
        )

        let report = session.doctor(path: projectPath)

        try expect(
            report.warnings.contains {
                $0.contains("access method")
                    && $0.contains("Work")
                    && $0.contains("Personal")
            },
            "doctor should warn when folder SSH conflicts with global HTTPS"
        )
    }),
    ("folder assignment defaults use cwd active profile and infer single-repo from .git", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoPath = temporaryDirectory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoPath.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let plainPath = temporaryDirectory.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: plainPath, withIntermediateDirectories: true)
        let active = try GitProfile(
            id: "personal",
            displayName: "Personal",
            gitUserName: "Personal",
            gitUserEmail: "me@example.com",
            sshKeyPath: "~/.ssh/id_ed25519",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )

        let inferredRepo = try FolderAssignmentDefaults.resolve(
            path: nil,
            profileReference: nil,
            mode: nil,
            activeProfile: active,
            currentDirectory: repoPath.path,
            homeDirectory: temporaryDirectory
        )
        try expect(inferredRepo.path == repoPath.path, "path should default to cwd")
        try expect(inferredRepo.profileReference == "personal", "profile should default to active id")
        try expect(inferredRepo.matchMode == .singleRepo, "git repo should default to single-repo")

        let inferredPlain = try FolderAssignmentDefaults.resolve(
            path: plainPath.path,
            profileReference: nil,
            mode: nil,
            activeProfile: active,
            currentDirectory: temporaryDirectory.path,
            homeDirectory: temporaryDirectory
        )
        try expect(inferredPlain.matchMode == .folderTree, "non-repo folder should default to folder-tree")

        try expectThrows(FolderAssignmentDefaults.ResolutionError.missingActiveProfile, {
            _ = try FolderAssignmentDefaults.resolve(
                path: nil,
                profileReference: nil,
                mode: nil,
                activeProfile: nil,
                currentDirectory: repoPath.path,
                homeDirectory: temporaryDirectory
            )
        }, "missing active profile should fail when --profile is omitted")
    }),
    ("profile settings manager reapply writes insteadOf into managed profile config", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let profile = try GitProfile(
            id: "personal",
            displayName: "Personal",
            gitUserName: "kwiats",
            gitUserEmail: "me@example.com",
            sshKeyPath: "~/.ssh/id_ed25519_kwiats",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [profile]))
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [],
            gitConfigInstaller: ManagedGitConfigInstaller(homeDirectory: temporaryDirectory),
            homeDirectory: temporaryDirectory
        )

        try manager.reapplyManagedGitConfig()

        let profileConfig = try String(
            contentsOf: temporaryDirectory.appendingPathComponent(
                ".config/git-account-switcher/profiles/personal.gitconfig"
            ),
            encoding: .utf8
        )
        try expect(profileConfig.contains("[url \"git@github.com:\"]"), "reapply should emit SSH insteadOf")
        try expect(profileConfig.contains("insteadOf = https://github.com/"), "reapply should rewrite HTTPS remotes")
    }),
    ("switch commit session resolves show and delete references", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let work = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            sshKeyPath: "~/.ssh/id_work",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let store = ProfileStore(fileURL: temporaryDirectory.appendingPathComponent("profiles.json"))
        try store.save(ProfileStoreData(profiles: [work]))
        let session = try SwitchCommitSession(
            profileStore: store,
            keychainStore: InMemoryKeychainStore(),
            gitConfigInstaller: nil,
            homeDirectory: temporaryDirectory
        )

        let shownProfile = try session.show(reference: "WORK")
        try expect(shownProfile == work, "show should use case-insensitive display-name resolution")
        try session.deleteProfile(reference: "work")

        try expect(session.profiles.isEmpty, "delete should resolve and remove the selected profile")
        try expectThrows(ProfileReferenceError.notFound("work"), {
            _ = try session.show(reference: "work")
        }, "show should report missing profiles")
    }),
    ("switch commit session adds and edits profiles", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(fileURL: temporaryDirectory.appendingPathComponent("profiles.json"))
        let session = try SwitchCommitSession(
            profileStore: store,
            keychainStore: InMemoryKeychainStore(),
            gitConfigInstaller: nil,
            homeDirectory: temporaryDirectory
        )

        let addedProfile = try session.addProfile(
            displayName: "Personal",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com",
            accessMethod: .https,
            sshKeyPath: "",
            hosts: ["github.com"],
            httpsCredentialRef: "git-account-switcher.personal.https"
        )
        let editedProfile = try session.editProfile(
            reference: addedProfile.id,
            displayName: "Personal GitHub",
            hosts: ["github.com", "github.enterprise.example"]
        )

        try expect(
            editedProfile.displayName == "Personal GitHub",
            "edit should update a profile resolved by its identifier"
        )
        try expect(
            editedProfile.hosts == ["github.com", "github.enterprise.example"],
            "edit should replace configured hosts"
        )
        let persisted = try store.load()
        try expect(
            persisted.profiles == [editedProfile],
            "add and edit should persist the updated profile metadata"
        )
    }),
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
        let profile = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "W",
            gitUserEmail: "w@example.com",
            accessMethod: .https,
            sshKeyPath: "",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let snapshot = StatusSnapshot(
            activeProfile: profile,
            contextProfile: profile,
            contextPath: "/Users/demo/project",
            contextSource: .global
        )
        let text = CLIOutput.humanStatus(
            snapshot: snapshot,
            style: CLIOutput.Style(colorEnabled: false)
        )
        try expect(!text.contains("\u{001B}["), "no ANSI when disabled")
    }),
    ("cli output uses ansi when color enabled", {
        let profile = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "W",
            gitUserEmail: "w@example.com",
            accessMethod: .https,
            sshKeyPath: "",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let text = CLIOutput.humanList(
            profiles: [profile],
            activeProfileId: "work",
            style: CLIOutput.Style(colorEnabled: true)
        )
        try expect(text.contains("\u{001B}["), "ANSI should appear when color enabled")
    }),
    ("cli output json error envelope", {
        let json = CLIOutput.jsonError("unknown profile")
        try expect(json.contains("\"ok\":false"), "error envelope required")
        try expect(json.contains("unknown profile"), "message required")
    }),
    ("cli output style detect respects no color flag", {
        let style = CLIOutput.Style.detect(noColorFlag: true, isTTY: true, env: [:])
        try expect(!style.colorEnabled, "--no-color should disable color")
    }),
    ("cli output style detect respects no color env", {
        let style = CLIOutput.Style.detect(noColorFlag: false, isTTY: true, env: ["NO_COLOR": "1"])
        try expect(!style.colorEnabled, "NO_COLOR should disable color")
    }),
    ("cli output style detect respects non tty", {
        let style = CLIOutput.Style.detect(noColorFlag: false, isTTY: false, env: [:])
        try expect(!style.colorEnabled, "non-tty should disable color")
    }),
    ("cli output style detect enables color on tty", {
        let style = CLIOutput.Style.detect(noColorFlag: false, isTTY: true, env: [:])
        try expect(style.colorEnabled, "tty without no-color should enable color")
    }),
    ("cli output json ok envelope", {
        let json = CLIOutput.jsonOK()
        try expect(json.contains("\"ok\":true"), "ok envelope required")
        try expect(!json.contains("\"error\""), "ok envelope should not include error")
    }),
    ("profile settings manager reloadFromStore picks up externally added folder rule", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        let work = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            sshKeyPath: "~/.ssh/id_work",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [work], rules: []))
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [work]
        )
        try expect(manager.rules.isEmpty, "manager starts with no rules")

        let externalRule = try FolderRule(
            id: "rule-external",
            path: "/Users/me/Work",
            profileId: "work",
            matchMode: .folderTree,
            enabled: true
        )
        try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [work], rules: [externalRule]))
        try manager.reloadFromStore()

        try expect(manager.rules == [externalRule], "reload should load externally added rule")
        try expect(
            manager.rules(forProfileId: "work").map(\.id) == ["rule-external"],
            "reloaded rule should appear for profile"
        )
    }),
    ("profile settings manager reloadFromStore drops externally removed folder rule", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        let work = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            sshKeyPath: "~/.ssh/id_work",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let rule = try FolderRule(
            id: "rule-1",
            path: "/Users/me/Work",
            profileId: "work",
            matchMode: .folderTree,
            enabled: true
        )
        try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [work], rules: [rule]))
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [work]
        )
        try expect(manager.rules.count == 1, "manager starts with one rule")

        try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [work], rules: []))
        try manager.reloadFromStore()

        try expect(manager.rules.isEmpty, "reload should drop externally removed rule")
    }),
    ("profile settings manager write reloads disk rules before persisting", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        let work = try GitProfile(
            id: "work",
            displayName: "Work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            sshKeyPath: "~/.ssh/id_work",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [work], rules: []))
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [work]
        )
        try expect(manager.rules.isEmpty, "stale manager has empty rules")

        let externalRule = try FolderRule(
            id: "cli-rule",
            path: "/Users/me/CLI",
            profileId: "work",
            matchMode: .folderTree,
            enabled: true
        )
        try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [work], rules: [externalRule]))

        try manager.updateSelectedProfileDisplayName("Work Renamed")

        let loaded = try ProfileStore(fileURL: storeURL).load()
        try expect(loaded.rules == [externalRule], "unrelated write must not wipe CLI rules")
        try expect(loaded.profiles.first?.displayName == "Work Renamed", "local rename still persists")
        try expect(manager.rules == [externalRule], "manager memory should include reloaded rule")
    }),
    ("profile settings manager adds persisted folder rule and reapplies config", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
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
        let storeURL = temporaryDirectory.appendingPathComponent("profiles.json")
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [profile],
            gitConfigInstaller: ManagedGitConfigInstaller(homeDirectory: temporaryDirectory)
        )
        let rulePath = temporaryDirectory.appendingPathComponent("Projects/Work").path

        let rule = try manager.addFolderRule(path: rulePath, profileId: "work")

        try expect(rule.path == rulePath, "added rule should retain its normalized absolute path")
        try expect(manager.rules == [rule], "added rule should be available from manager state")
        let loaded = try ProfileStore(fileURL: storeURL).load()
        try expect(loaded.rules == [rule], "added rule should persist")
        let rulesConfig = try String(
            contentsOf: temporaryDirectory.appendingPathComponent(".config/git-account-switcher/rules.gitconfig"),
            encoding: .utf8
        )
        try expect(rulesConfig.contains(rulePath), "rules config should contain the added path")
        try expect(rulesConfig.contains("profiles/work.gitconfig"), "rules config should include the selected profile")
    }),
    ("profile settings manager moves folder rule after confirmed takeover", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let personal = try GitProfile(
            id: "personal",
            displayName: "Personal",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com",
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
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: false
        )
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: temporaryDirectory.appendingPathComponent("profiles.json")),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [personal, work]
        )
        let rulePath = temporaryDirectory.appendingPathComponent("Projects/Shared").path
        _ = try manager.addFolderRule(path: rulePath, profileId: "personal")

        try expectThrows(
            FolderRuleMutationError.ownedByOtherProfile(profileId: "personal"),
            {
                _ = try manager.addFolderRule(path: "\(rulePath)/", profileId: "work")
            },
            "unconfirmed ownership takeover should fail"
        )
        let moved = try manager.addFolderRule(
            path: "\(rulePath)/",
            profileId: "work",
            moveIfOwned: true
        )

        try expect(moved.profileId == "work", "confirmed takeover should change the rule owner")
        try expect(manager.rules.count == 1, "takeover should retain one rule for the path")
    }),
    ("profile settings manager validates profile id before folder rule takeover", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let personal = try GitProfile(
            id: "personal",
            displayName: "Personal",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com",
            sshKeyPath: "~/.ssh/id_personal",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: true
        )
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: temporaryDirectory.appendingPathComponent("profiles.json")),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [personal]
        )
        let rulePath = temporaryDirectory.appendingPathComponent("Projects/Shared").path
        let originalRule = try manager.addFolderRule(path: rulePath, profileId: "personal")

        try expectThrows(SwitchCommitError.unsafeIdentifier, {
            _ = try manager.addFolderRule(
                path: rulePath,
                profileId: "../evil",
                moveIfOwned: true
            )
        }, "unsafe profile ids must be rejected before takeover")
        try expectThrows(FolderRuleMutationError.profileNotFound(profileId: "missing"), {
            _ = try manager.addFolderRule(path: rulePath, profileId: "missing", moveIfOwned: true)
        }, "missing profiles must be rejected before takeover")
        try expect(manager.rules == [originalRule], "failed takeover should preserve the original rule")
    }),
    ("profile settings manager lists and removes folder rules by profile path and id", {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let personal = try GitProfile(
            id: "personal",
            displayName: "Personal",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com",
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
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: false
        )
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: temporaryDirectory.appendingPathComponent("profiles.json")),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [personal, work]
        )
        let personalRule = try manager.addFolderRule(
            path: temporaryDirectory.appendingPathComponent("Personal").path,
            profileId: "personal"
        )
        let workRule = try manager.addFolderRule(
            path: temporaryDirectory.appendingPathComponent("Work").path,
            profileId: "work"
        )

        try expect(manager.rules(forProfileId: "personal") == [personalRule], "rules listing should filter to requested profile")
        try manager.removeFolderRule(path: "\(workRule.path)/")
        try expect(manager.rules == [personalRule], "path removal should normalize paths")
        try manager.removeFolderRule(id: personalRule.id)
        try expect(manager.rules.isEmpty, "id removal should remove the remaining rule")
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
    ("profile settings manager applies folder rules through git config installer", {
        final class RecordingInstaller: GitConfigInstalling {
            var appliedRules: [FolderRule] = []

            func apply(profiles: [GitProfile], rules: [FolderRule], activeProfile: GitProfile?) throws {
                appliedRules = rules
            }
        }

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
        let installer = RecordingInstaller()
        let manager = try ProfileSettingsManager(
            profileStore: ProfileStore(fileURL: storeURL),
            keychainStore: InMemoryKeychainStore(),
            seedProfiles: [work],
            gitConfigInstaller: installer
        )

        try manager.addFolderRule(
            path: "/Users/me/Work",
            profileId: "work",
            matchMode: .folderTree,
            forceMove: false
        )

        try expect(installer.appliedRules.count == 1, "apply should receive new rules")
        try expect(installer.appliedRules[0].profileId == "work", "apply should receive work rule")
        try expect(installer.appliedRules[0].path == "/Users/me/Work", "apply should receive normalized path")
    }),
    ("profile settings manager rejects unknown profile for folder rule", {
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
        try expectThrows(FolderRuleError.unknownProfile, {
            try manager.addFolderRule(
                path: "/Users/me/Work",
                profileId: "nonexistent",
                matchMode: .folderTree,
                forceMove: false
            )
        }, "unknown profile")
    }),
    ("profile settings manager rejects removing unknown folder rule", {
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
        try expectThrows(FolderRuleError.ruleNotFound, {
            try manager.removeFolderRule(id: "missing-rule-id")
        }, "unknown rule id")
    }),
    ("profile settings manager upserts same-profile folder rule match mode", {
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
        try manager.addFolderRule(path: "/Users/me/Work", profileId: "work", matchMode: .singleRepo, forceMove: false)
        let rules = manager.rules(forProfileId: "work")
        try expect(rules.count == 1, "still one rule")
        try expect(rules[0].matchMode == .singleRepo, "match mode updated")
    }),
    ("profile settings manager detects normalized path conflict", {
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
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sharedPath = "\(home)/Shared"
        try manager.addFolderRule(path: "~/Shared", profileId: "work", matchMode: .folderTree, forceMove: false)
        try expectThrows(FolderRuleError.pathOwnedByOtherProfile(profileId: "work"), {
            try manager.addFolderRule(path: sharedPath, profileId: "personal", matchMode: .folderTree, forceMove: false)
        }, "tilde vs absolute conflict")
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
            var successfulUpdateCycleHandler: (() -> Void)?
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
            var successfulUpdateCycleHandler: (() -> Void)?
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
    ("app view model syncs CLI after successful update check", {
        let installer = FakeCLIInstaller(statusMessage: "CLI is installed at /usr/local/bin/switch-commit.")
        let viewModel = AppViewModel(profiles: [], cliInstaller: installer)
        viewModel.syncCLIAfterSuccessfulUpdateCheck()
        try expect(installer.installCallCount == 1, "successful update cycle should repair CLI")
        try expect(
            viewModel.settingsMessage == "CLI synced with Switch Commit.",
            "settings should confirm CLI sync"
        )
        try expect(
            viewModel.cliInstallStatusText == "CLI is installed at /usr/local/bin/switch-commit.",
            "CLI status should refresh after sync"
        )
    }),
    ("app view model reports CLI sync failure after successful update check", {
        let installer = FakeCLIInstaller(statusMessage: "CLI is missing from /usr/local/bin/switch-commit.")
        installer.errorToThrow = FakeCLIInstallerError.denied
        let viewModel = AppViewModel(profiles: [], cliInstaller: installer)
        viewModel.syncCLIAfterSuccessfulUpdateCheck()
        try expect(installer.installCallCount == 1, "sync should still attempt repair")
        try expect(
            viewModel.settingsMessage?.contains("Could not sync CLI") == true,
            "settings should surface sync failure without undoing app update"
        )
    }),
    ("menu bar app relauncher no-ops when app is not running", {
        final class RecordingRunner: CommandRunning {
            private(set) var commands: [(String, [String])] = []
            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                commands.append((command, arguments))
                return CommandResult(exitCode: 1, standardOutput: "false\n", standardError: "")
            }
        }
        let runner = RecordingRunner()
        let relauncher = MenuBarAppRelauncher(commandRunner: runner)
        let didRelaunch = try relauncher.relaunchIfRunning()
        try expect(!didRelaunch, "should not relaunch when not running")
        try expect(runner.commands.count == 1, "only the running check should run")
        try expect(runner.commands[0].0 == "osascript", "running check should use osascript")
    }),
    ("menu bar app relauncher quits then opens when app is running", {
        final class RecordingRunner: CommandRunning {
            private(set) var commands: [(String, [String])] = []
            func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
                commands.append((command, arguments))
                return CommandResult(exitCode: 0, standardOutput: "true\n", standardError: "")
            }
        }
        let runner = RecordingRunner()
        let relauncher = MenuBarAppRelauncher(commandRunner: runner)
        let didRelaunch = try relauncher.relaunchIfRunning()
        try expect(didRelaunch, "should relaunch when running")
        try expect(runner.commands.count == 3, "probe + quit + open")
        try expect(runner.commands[0].0 == "osascript", "probe uses osascript")
        try expect(runner.commands[1].0 == "osascript", "quit uses osascript")
        try expect(
            runner.commands[1].1.contains(where: { $0.contains("quit") }),
            "second command should quit the app"
        )
        try expect(runner.commands[2].0 == "open", "third command opens the app")
        try expect(
            runner.commands[2].1 == ["/Applications/Switch Commit.app"],
            "open should target the installed app path"
        )
    }),
    ("update command relaunches menu bar app after install", {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SwitchCommitCLI/Commands/UpdateCommand.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        try expect(source.contains("MenuBarAppRelauncher"), "update should use MenuBarAppRelauncher")
        try expect(source.contains("relaunchIfRunning"), "update should attempt relaunch after install")
        try expect(
            source.contains("Could not restart Switch Commit"),
            "update should warn when relaunch fails without failing the install"
        )
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
        try expect(source.contains("successfulUpdateCycleHandler"), "sparkle adapter should expose a successful cycle handler for CLI sync")
        try expect(source.contains("updaterWillRelaunchApplication"), "sparkle adapter should sync CLI before relaunch")
        try expect(source.contains("didFinishUpdateCycleFor"), "sparkle adapter should observe finished update cycles")
        try expect(source.contains("SUError.noUpdateError") || source.contains("noUpdateError"), "sparkle adapter should treat already-up-to-date as success for CLI sync")
        try expect(
            source.contains("SUSparkleErrorDomain"),
            "sparkle adapter should only treat Sparkle no-update errors as successful sync triggers"
        )
    }),
    ("app wires successful sparkle cycle to CLI sync", {
        let appURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SwitchCommitApp/SwitchCommitApp.swift")
        let source = try String(contentsOf: appURL, encoding: .utf8)
        try expect(
            source.contains("successfulUpdateCycleHandler"),
            "app should wire sparkle success handler"
        )
        try expect(
            source.contains("syncCLIAfterSuccessfulUpdateCheck"),
            "app should sync CLI after a successful update cycle"
        )
    }),
    ("release build script embeds Switch Commit Sparkle channel configuration", {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Scripts/build-release.sh")
        let source = try String(contentsOf: scriptURL, encoding: .utf8)

        try expect(
            source.contains("release_channel_base_url=\"https://kwiats.github.io/switch-commit\"")
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
            source.contains("release_channel_base_url=\"https://kwiats.github.io/switch-commit\""),
            "release script should keep the public channel base URL in one place"
        )
        try expect(
            source.contains("sparkle_feed_url=\"${release_channel_base_url}/appcast.xml\""),
            "release script should derive appcast URL from the public channel base URL"
        )
        try expect(source.contains("app_name=\"Switch Commit\""), "release script should ship Switch Commit.app")
        try expect(source.contains("binary_name=\"SwitchCommitApp\""), "release script should build SwitchCommitApp")
        try expect(
            source.contains("sparkle_artifact_url=\"https://github.com/kwiats/switch-commit/releases/download/v${version}/SwitchCommit-v${version}-macOS.dmg\""),
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
    ("release build script packages the switch-commit CLI", {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Scripts/build-release.sh")
        let source = try String(contentsOf: scriptURL, encoding: .utf8)

        try expect(
            source.contains("swift build -c release --product switch-commit"),
            "release script should build the switch-commit CLI product"
        )
        try expect(
            source.contains("Contents/MacOS/switch-commit"),
            "release script should embed the CLI in the app bundle"
        )
        try expect(
            source.contains("pkgbuild") || source.contains("productbuild"),
            "release script should build an installer package"
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
        try expect(source.contains("kwiats/switch-commit"), "publisher should target this public repository for Releases")
        try expect(!source.contains("switch-commit-release-channel"), "publisher should not target the legacy channel repository")
        try expect(source.contains("SwitchCommit-v${version}-macOS.dmg"), "publisher should upload the release DMG")
        try expect(!source.contains("macOS.zip"), "publisher should not publish a ZIP artifact")
        try expect(source.contains("checksum_name=\"${artifact_name}.sha256\""), "publisher should upload the checksum")
        try expect(source.contains("CHANGELOG.md"), "publisher should require root CHANGELOG.md")
        try expect(
            source.contains("Scripts/site-landing/extract-release-notes.mjs"),
            "publisher should extract version notes from CHANGELOG.md"
        )
        try expect(
            source.contains("missing release notes"),
            "publisher must fail when release notes are missing instead of publishing an empty body"
        )
        try expect(
            !source.contains("--notes \"Switch Commit ${version}\""),
            "publisher must not fall back to a stub GitHub Release body"
        )
        try expect(
            source.contains("notes_asset_path=\"${release_dir}/SwitchCommit-v${version}-macOS.md\""),
            "publisher should stage release notes under the Sparkle releaseNotesLink asset name"
        )
        try expect(
            source.contains("release_assets=(\"${artifact_path}\" \"${checksum_path}\" \"${notes_asset_path}\")")
                || source.contains("release_assets+=(\"${notes_asset_path}\")"),
            "publisher must upload the release notes markdown asset so Sparkle can download it"
        )
        try expect(
            source.contains("--download-url-prefix \"${github_download_prefix}/\""),
            "publisher should put GitHub Releases download URLs inside appcast enclosures"
        )
        try expect(
            source.contains("--release-notes-url-prefix \"${github_download_prefix}/\""),
            "publisher should point Sparkle releaseNotesLink at the uploaded notes asset URL"
        )
        try expect(source.contains("site/version.txt") || source.contains("version.txt"), "publisher should write the latest version marker for Pages")
        try expect(source.contains("site_dir"), "publisher should write channel metadata under site/")
        try expect(!source.contains("docs/release-channel/index.html"), "publisher must not overwrite the Pages landing from a template")
        try expect(!source.contains("index.html"), "publisher must not write site/index.html; landing sync owns it")
        try expect(source.contains("rm -rf"), "publisher should remove obsolete Pages artifact folders")
        try expect(source.contains("-o \"${site_dir}/appcast.xml\""), "publisher should keep appcast.xml under site/")
    }),
    ("tag release workflow publishes public GitHub Pages appcast channel", {
        let workflowURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".github/workflows/release.yml")
        let source = try String(contentsOf: workflowURL, encoding: .utf8)

        try expect(source.contains("tags:"), "release workflow should run for tags")
        try expect(source.contains("'v*'"), "release workflow should limit publishing to v-prefixed tags")
        try expect(source.contains("Scripts/pr-checks.sh"), "release workflow should run local checks before publishing")
        try expect(source.contains("Scripts/build-release.sh"), "release workflow should build the release artifact")
        try expect(!source.contains("repository: kwiats/switch-commit-release-channel"), "release workflow should not checkout the legacy channel repository")
        try expect(!source.contains("RELEASE_CHANNEL_TOKEN"), "release workflow should not require a cross-repo release channel token")
        try expect(source.contains("SPARKLE_PRIVATE_ED_KEY"), "release workflow should provide Sparkle signing material only from secrets")
        try expect(source.contains("GH_TOKEN: ${{ github.token }}"), "release workflow should authenticate gh release with the job token")
        try expect(source.contains("Scripts/publish-release-channel.sh"), "release workflow should publish through the checked-in publisher script")
        try expect(
            source.contains("Scripts/site-landing/sync-landing.mjs"),
            "release workflow should sync landing changelog/CTA after publishing the GitHub Release"
        )
        try expect(
            source.contains("site/index.html"),
            "release workflow should include landing HTML in the site metadata PR"
        )
        try expect(source.contains("site/appcast.xml"), "release workflow should publish site appcast metadata")
        try expect(source.contains("gh pr create"), "release workflow should open a PR because main requires pull requests")
        try expect(source.contains("gh pr merge"), "release workflow should merge the site metadata PR")
        try expect(
            source.contains("gh workflow run \"Deploy GitHub Pages\""),
            "release workflow should dispatch Pages deploy after merging site metadata"
        )
        try expect(source.contains("pull-requests: write"), "release workflow should request pull-requests write permission")
    }),
    ("README documents tag release CD and release channel secrets", {
        let readmeURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("README.md")
        let source = try String(contentsOf: readmeURL, encoding: .utf8)

        try expect(source.contains("git tag v0.2.0"), "README should show how to tag a release")
        try expect(source.contains("CHANGELOG.md"), "README should document required CHANGELOG.md path")
        try expect(!source.contains("RELEASE_CHANNEL_TOKEN"), "README should not require a legacy cross-repo release channel token")
        try expect(source.contains("SPARKLE_PRIVATE_ED_KEY"), "README should document the Sparkle private key secret")
        try expect(source.contains("generate_keys -x /tmp/sparkle-private-key.txt"), "README should show how to export the Sparkle private key")
        try expect(source.contains("Do not use the public SUPublicEDKey value"), "README should warn against using the public key as the private secret")
        try expect(source.contains("https://kwiats.github.io/switch-commit/appcast.xml"), "README should document the public appcast URL")
        try expect(source.contains("site/version.txt") || source.contains("version.txt"), "README should document the Pages version marker")
        try expect(source.contains("site/index.html") || source.contains("site/"), "README should document the site/ Pages root")
        try expect(
            source.contains("https://github.com/kwiats/switch-commit/releases/download/"),
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
    ("settings navigation avoids NavigationSplitView blanking Updates", {
        let settingsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SwitchCommitApp/SettingsView.swift")
        let windowURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SwitchCommitApp/SettingsWindowController.swift")
        let smokeURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SwitchCommitApp/SettingsNavigationSmoke.swift")
        let appURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SwitchCommitApp/SwitchCommitApp.swift")
        let settingsSource = try String(contentsOf: settingsURL, encoding: .utf8)
        let windowSource = try String(contentsOf: windowURL, encoding: .utf8)
        let smokeSource = try String(contentsOf: smokeURL, encoding: .utf8)
        let appSource = try String(contentsOf: appURL, encoding: .utf8)

        try expect(
            !settingsSource.contains("NavigationSplitView"),
            "Settings must not use NavigationSplitView; it blanks the window when selecting Updates"
        )
        try expect(
            !settingsSource.contains("NavigationLink(value:"),
            "Settings sidebar must not use NavigationLink values inside a hosted split view"
        )
        try expect(
            settingsSource.contains("HStack(spacing: 0)"),
            "Settings should use an explicit HStack sidebar + detail chrome"
        )
        try expect(
            settingsSource.contains(".listStyle(.sidebar)"),
            "Settings section list should use sidebar list style"
        )
        try expect(
            settingsSource.contains("accessibilityIdentifier(\"settings.tab.\\(tab.rawValue)\")"),
            "Updates tab needs a stable accessibility identifier for smoke coverage"
        )
        try expect(
            settingsSource.contains("accessibilityIdentifier(\"settings.detail.updates\")"),
            "Updates detail needs a stable accessibility identifier for smoke coverage"
        )
        try expect(
            windowSource.contains("window.contentViewController = hostingController"),
            "Settings window must reinstall hosting content on each show for recovery"
        )
        try expect(
            smokeSource.contains("SettingsNavigationSmoke"),
            "App target must include a Settings navigation smoke harness"
        )
        try expect(
            appSource.contains("--smoke-settings-navigation"),
            "App entrypoint must expose --smoke-settings-navigation for end-to-end Settings tab checks"
        )
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
    }),
    ("CLI output formats doctor reports for people and JSON clients", {
        let report = DiagnosticsReport(
            values: [
                "user.email": "file:.gitconfig\tme@example.com",
                "user.name": "file:.gitconfig\tMe"
            ],
            warnings: ["core.sshCommand: unset"]
        )

        let human = CLIOutput.humanDoctor(report: report, style: .init(colorEnabled: false))
        try expect(human.contains("user.email: file:.gitconfig\tme@example.com"), "human doctor output should include values")
        try expect(human.contains("Warnings:"), "human doctor output should label warnings")
        try expect(human.contains("core.sshCommand: unset"), "human doctor output should include warnings")

        let json = CLIOutput.jsonDoctor(report: report)
        try expect(json.contains("\"ok\":true"), "JSON doctor output should report success")
        try expect(json.contains("\"values\""), "JSON doctor output should include values")
        try expect(json.contains("\"warnings\""), "JSON doctor output should include warnings")
    }),
    ("app view model exposes CLI installer status from injected manager", {
        try MainActor.assumeIsolated {
            let installer = FakeCLIInstaller(statusMessage: "CLI is installed at /usr/local/bin/switch-commit.")
            let viewModel = AppViewModel(profiles: [], cliInstaller: installer)

            try expect(
                viewModel.cliInstallStatusText == "CLI is installed at /usr/local/bin/switch-commit.",
                "view model should expose the injected CLI installer status"
            )
            try expect(viewModel.isCLIInstalled, "installed status should select the reinstall action")
        }
    }),
    ("app view model installs CLI through injected manager", {
        try MainActor.assumeIsolated {
            let installer = FakeCLIInstaller(statusMessage: "CLI is missing from /usr/local/bin/switch-commit.")
            let viewModel = AppViewModel(profiles: [], cliInstaller: installer)

            viewModel.installCLI()

            try expect(installer.installCallCount == 1, "install should call the injected CLI installer")
            try expect(
                viewModel.cliInstallStatusText == "CLI is missing from /usr/local/bin/switch-commit.",
                "view model should refresh and expose the installer status after install"
            )
        }
    }),
    ("app view model exposes CLI installation failure", {
        try MainActor.assumeIsolated {
            let installer = FakeCLIInstaller(statusMessage: "CLI is missing from /usr/local/bin/switch-commit.")
            installer.errorToThrow = FakeCLIInstallerError.denied
            let viewModel = AppViewModel(profiles: [], cliInstaller: installer)

            viewModel.installCLI()

            try expect(
                viewModel.cliInstallStatusText.contains("Could not install CLI"),
                "view model should expose a CLI installation failure"
            )
        }
    }),
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
    ("view model reloadFromProfileStore surfaces externally added folder rule", {
        try MainActor.assumeIsolated {
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
            viewModel.selectProfile(id: "work")
            try expect(viewModel.folderAssignmentsForSelectedProfile.isEmpty, "starts empty")

            let rule = try FolderRule(
                id: "cli-1",
                path: "/Users/me/Work",
                profileId: "work",
                matchMode: .folderTree,
                enabled: true
            )
            try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [work], rules: [rule]))
            viewModel.reloadFromProfileStore()

            try expect(
                viewModel.folderAssignmentsForSelectedProfile.map(\.id) == ["cli-1"],
                "Settings rows should show CLI-added rule after reload"
            )
        }
    }),
    ("view model reloadFromProfileStore drops externally removed folder rule", {
        try MainActor.assumeIsolated {
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
            let rule = try FolderRule(
                id: "cli-1",
                path: "/Users/me/Work",
                profileId: "work",
                matchMode: .folderTree,
                enabled: true
            )
            try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [work], rules: [rule]))
            let viewModel = AppViewModel(
                profileStore: ProfileStore(fileURL: storeURL),
                keychainStore: InMemoryKeychainStore(),
                gitConfigInstaller: nil
            )
            viewModel.selectProfile(id: "work")
            try expect(viewModel.folderAssignmentsForSelectedProfile.count == 1, "starts with rule")

            try ProfileStore(fileURL: storeURL).save(ProfileStoreData(profiles: [work], rules: []))
            viewModel.reloadFromProfileStore()

            try expect(
                viewModel.folderAssignmentsForSelectedProfile.isEmpty,
                "Settings rows should clear after CLI remove"
            )
        }
    }),
    ("view model lists folder rules for selected profile only", {
        try MainActor.assumeIsolated {
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
        }
    }),
    ("view model add folder rule updates rows and bumps menu revision", {
        try MainActor.assumeIsolated {
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
        }
    }),
    ("view model apply same frontmost path twice does not bump menu revision twice", {
        try MainActor.assumeIsolated {
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
            let before = viewModel.menuContentRevision
            viewModel.applyFrontmostPath("/Users/me/Work", source: .terminal)
            let afterFirst = viewModel.menuContentRevision
            try expect(afterFirst == before + 1, "first apply bumps revision")
            viewModel.applyFrontmostPath("/Users/me/Work", source: .finder)
            try expect(viewModel.menuContentRevision == afterFirst, "second apply keeps revision")
        }
    }),
    ("view model apply frontmost path shows folder context without changing active profile", {
        try MainActor.assumeIsolated {
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
        }
    }),
    ("view model apply unavailable context keeps degraded header", {
        try MainActor.assumeIsolated {
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
        }
    }),
    ("view model clear frontmost path falls back to global", {
        try MainActor.assumeIsolated {
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
