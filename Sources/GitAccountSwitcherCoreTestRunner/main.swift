import Foundation
import GitAccountSwitcherAppLogic
import GitAccountSwitcherCore

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

extension DetectedGitAccount {
    var displaySummary: String {
        username ?? gitUserName ?? gitUserEmail ?? "GitHub Account"
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
        let signal = GitRemoteParser().signal(from: "https://github.com/pawelkwiatkowski/project.git")

        try expect(signal?.confidence == .medium, "remote signal should have medium confidence")
        try expect(signal?.source == .repositoryRemote, "remote signal should identify repository remote source")
        try expect(signal?.hosts == ["github.com"], "remote signal should identify github.com")
        try expect(signal?.username == nil, "remote owner should not become a username")
        try expect(signal?.warnings == ["Remote owner 'pawelkwiatkowski' may be a user or an organization."], "remote signal should warn about owner ambiguity")
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
    }),
    ("profile rejects empty commit identity", {
        try expectThrows(GitAccountSwitcherError.emptyGitUserName, {
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
    ("profile rejects config injection characters", {
        try expectThrows(GitAccountSwitcherError.unsafeConfigValue, {
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

        try expectThrows(GitAccountSwitcherError.unsafeConfigValue, {
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
        try expectThrows(GitAccountSwitcherError.unsafeIdentifier, {
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
    ("folder rule rejects unsafe config paths and identifiers", {
        try expectThrows(GitAccountSwitcherError.unsafeConfigValue, {
            _ = try FolderRule(
                id: "work-folder",
                path: "/Users/me/Work\n[alias]\n    leak = !env",
                profileId: "work",
                matchMode: .folderTree,
                enabled: true
            )
        }, "folder paths should not allow newline injection")

        try expectThrows(GitAccountSwitcherError.unsafeIdentifier, {
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
        try expectThrows(GitAccountSwitcherError.writeOutsideManagedRoots, {
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
        try expectThrows(GitAccountSwitcherError.writeOutsideManagedRoots, {
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
        try expect(runner.commands.allSatisfy { $0.contains("--show-origin") }, "diagnostics should show origin")
        try expect(report.warnings.contains { $0.contains("core.sshCommand") }, "failed command should become warning")
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
