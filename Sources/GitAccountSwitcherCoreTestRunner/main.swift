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
