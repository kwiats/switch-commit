import Foundation
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

let tests: [(String, () throws -> Void)] = [
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
        let rule = FolderRule(
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
        try expect(profileConfig.contains("sshCommand = ssh -i ~/.ssh/id_work -F ~/.ssh/config"), "profile config should contain ssh command")

        let includeConfig = generator.rootIncludeConfig(
            globalConfigPath: "~/.config/git-account-switcher/global.gitconfig",
            rulesConfigPath: "~/.config/git-account-switcher/rules.gitconfig"
        )
        let globalRange = try expectRange(of: "global.gitconfig", in: includeConfig)
        let rulesRange = try expectRange(of: "rules.gitconfig", in: includeConfig)
        try expect(globalRange.lowerBound < rulesRange.lowerBound, "global include should come before folder rules")

        let rule = FolderRule(id: "work", path: "/Users/me/Work", profileId: "work", matchMode: .folderTree, enabled: true)
        let rulesConfig = generator.rulesConfig(rules: [rule], profilesDirectory: "~/.config/git-account-switcher/profiles")
        try expect(rulesConfig.contains("[includeIf \"gitdir:/Users/me/Work/**\"]"), "folder tree rule should match children")
        try expect(rulesConfig.contains("path = ~/.config/git-account-switcher/profiles/work.gitconfig"), "rule should include profile config")
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
